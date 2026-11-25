# %% [markdown]
# # Session conversion-propensity model (Maven Fuzzy Factory)
#
# Predicts whether a website session ends in an order, using **only information
# available at or near the start of the session** (device, traffic source /
# campaign, landing page, repeat flag, hour, day of week, month).
# Funnel-step pageviews and all order fields are excluded to avoid leakage.
#
# Run: `python conversion_model.py --data-dir <folder with the 6 CSVs> --out-dir <output folder>`

# %%
import argparse
import json
import os
import sys

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from sklearn.calibration import calibration_curve
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.inspection import permutation_importance
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import average_precision_score, brier_score_loss, roc_auc_score
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, OrdinalEncoder

SEED = 42
TEST_START = "2014-10-01"  # train: 2012-03-19 .. 2014-09-30, test: 2014-10-01 .. 2015-03-19


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--data-dir", default=os.environ.get("DATA_DIR", "data"))
    p.add_argument("--out-dir", default=os.environ.get("OUT_DIR", "outputs"))
    # inside Jupyter, ignore the kernel's own argv
    args, _ = p.parse_known_args([] if "ipykernel" in sys.modules else None)
    return args


ARGS = parse_args()
DATA, OUT = ARGS.data_dir, ARGS.out_dir
CHARTS = os.path.join(OUT, "charts")
os.makedirs(CHARTS, exist_ok=True)
R = {}  # every reported number goes in here, then results.json / results_summary.md

# chart styling (validated reference palette, slots 1-2)
BLUE, ORANGE, INK, INK2, GRID, SURF = "#2a78d6", "#eb6834", "#0b0b0b", "#52514e", "#e4e3df", "#fcfcfb"
plt.rcParams.update({
    "figure.facecolor": SURF, "axes.facecolor": SURF, "axes.edgecolor": INK2,
    "axes.labelcolor": INK, "xtick.color": INK2, "ytick.color": INK2, "text.color": INK,
    "axes.grid": True, "grid.color": GRID, "grid.linewidth": 0.8,
    "axes.spines.top": False, "axes.spines.right": False, "font.size": 10, "figure.dpi": 150,
})

# %% [markdown]
# ## 1. Load and join the tables

# %%
sessions = pd.read_csv(os.path.join(DATA, "website_sessions.csv"), parse_dates=["created_at"])
pageviews = pd.read_csv(os.path.join(DATA, "website_pageviews.csv"), parse_dates=["created_at"])
orders = pd.read_csv(os.path.join(DATA, "orders.csv"), parse_dates=["created_at"])
order_items = pd.read_csv(os.path.join(DATA, "order_items.csv"))
refunds = pd.read_csv(os.path.join(DATA, "order_item_refunds.csv"))
products = pd.read_csv(os.path.join(DATA, "products.csv"))

R["n_sessions"] = int(len(sessions))
R["n_orders"] = int(len(orders))
assert orders.website_session_id.is_unique  # at most one order per session

# Landing page = FIRST pageview of the session (lowest pageview id). This is the only
# pageview information used; every later pageview (products, cart, shipping, billing,
# thank-you) is excluded because it is part of the outcome we are predicting.
landing = (pageviews.sort_values("website_pageview_id")
           .groupby("website_session_id")["pageview_url"].first().rename("landing_page"))

df = sessions.join(landing, on="website_session_id")
df["converted"] = df.website_session_id.isin(orders.website_session_id).astype(int)

# Traffic source: utm_source when tagged; otherwise organic (has a search referer) or direct.
df["traffic_source"] = np.where(df.utm_source.notna(), df.utm_source,
                                np.where(df.http_referer.notna(), "organic", "direct"))
df["campaign"] = df.utm_campaign.fillna("none")
df["device"] = df.device_type
df["repeat"] = df.is_repeat_session.map({0: "new", 1: "repeat"})
df["hour"] = df.created_at.dt.hour.astype(str).str.zfill(2)
df["dow"] = df.created_at.dt.day_name().str[:3]
df["month"] = df.created_at.dt.month.astype(str).str.zfill(2)

R["overall_conversion_rate"] = float(df.converted.mean())
R["missing_landing_page"] = int(df.landing_page.isna().sum())
print(f"sessions={R['n_sessions']:,} orders={R['n_orders']:,} "
      f"conversion={R['overall_conversion_rate']:.2%} missing landing={R['missing_landing_page']}")

# %% [markdown]
# ## 2. Leakage-safe features and time-based split

# %%
FEATURES = ["device", "traffic_source", "campaign", "landing_page", "repeat", "hour", "dow", "month"]
# Deliberately NOT used: any pageview after the landing page, session length / pageview count,
# order fields (price, items, product), refunds, user_id, website_session_id, timestamps as
# continuous trend (would encode "later = better" and not generalise), utm_content (ad variant,
# 1:1 with source/campaign here, so redundant).

train = df[df.created_at < TEST_START].copy()
test = df[df.created_at >= TEST_START].copy()
Xtr, ytr, Xte, yte = train[FEATURES], train.converted.values, test[FEATURES], test.converted.values

R["split"] = {
    "train_period": f"{train.created_at.min():%Y-%m-%d} to {train.created_at.max():%Y-%m-%d}",
    "test_period": f"{test.created_at.min():%Y-%m-%d} to {test.created_at.max():%Y-%m-%d}",
    "train_sessions": int(len(train)), "test_sessions": int(len(test)),
    "train_conversion_rate": float(ytr.mean()), "test_conversion_rate": float(yte.mean()),
    "test_days": int((test.created_at.max().normalize() - test.created_at.min().normalize()).days + 1),
}
unseen = {c: sorted(set(Xte[c]) - set(Xtr[c])) for c in FEATURES}
R["split"]["test_categories_unseen_in_train"] = {k: v for k, v in unseen.items() if v}
print(json.dumps(R["split"], indent=1))

# %% [markdown]
# ## 3. Models: class-weighted logistic regression (main) and gradient boosting (comparison)
#
# Both use `class_weight="balanced"`. Class weighting inflates predicted probabilities
# (the model is trained as if conversions were 50% of sessions), so for the calibration
# check and the revenue analysis we undo the re-weighting with the standard prior
# correction: odds_corrected = odds_raw * (w_neg / w_pos). This uses training data only.

# %%
REFERENCE = {"device": "desktop", "traffic_source": "gsearch", "campaign": "nonbrand",
             "landing_page": "/home", "repeat": "new", "hour": "12", "dow": "Mon", "month": "01"}

logreg = Pipeline([
    ("ohe", ColumnTransformer([("cat", OneHotEncoder(drop=[REFERENCE[c] for c in FEATURES],
                                                     handle_unknown="ignore"), FEATURES)])),
    ("clf", LogisticRegression(class_weight="balanced", C=1.0, max_iter=2000)),
])
gbm = Pipeline([
    ("ord", ColumnTransformer([("cat", OrdinalEncoder(handle_unknown="use_encoded_value",
                                                      unknown_value=-1), FEATURES)])),
    ("clf", HistGradientBoostingClassifier(categorical_features=list(range(len(FEATURES))),
                                           class_weight="balanced", learning_rate=0.05,
                                           max_iter=300, max_leaf_nodes=31, random_state=SEED)),
])
logreg.fit(Xtr, ytr)
gbm.fit(Xtr, ytr)

pos_w = len(ytr) / (2 * ytr.sum())
neg_w = len(ytr) / (2 * (len(ytr) - ytr.sum()))
ODDS_FACTOR = neg_w / pos_w


def corrected_proba(model, X):
    p = np.clip(model.predict_proba(X)[:, 1], 1e-9, 1 - 1e-9)
    odds = p / (1 - p) * ODDS_FACTOR
    return odds / (1 + odds)


# Simple non-ML baseline: train-period conversion rate of the session's device x source x landing page
seg_cols = ["device", "traffic_source", "landing_page"]
seg_rate = train.groupby(seg_cols).converted.mean().rename("seg_rate")
base_te = test.join(seg_rate, on=seg_cols)["seg_rate"].fillna(ytr.mean()).values

# %% [markdown]
# ## 4. Evaluation on the held-out later months

# %%
def evaluate(name, raw, corr):
    order = np.argsort(-corr, kind="stable")
    top = order[: int(np.ceil(0.10 * len(corr)))]
    top_rate = yte[top].mean()
    return {
        "model": name,
        "roc_auc": float(roc_auc_score(yte, raw)),
        "pr_auc": float(average_precision_score(yte, raw)),
        "top_decile_conversion_rate": float(top_rate),
        "top_decile_lift": float(top_rate / yte.mean()),
        "top_decile_share_of_orders": float(yte[top].sum() / yte.sum()),
        "mean_raw_predicted": float(np.mean(raw)),
        "mean_corrected_predicted": float(np.mean(corr)),
        "brier_corrected": float(brier_score_loss(yte, corr)),
    }


p_lr_raw, p_gb_raw = logreg.predict_proba(Xte)[:, 1], gbm.predict_proba(Xte)[:, 1]
p_lr, p_gb = corrected_proba(logreg, Xte), corrected_proba(gbm, Xte)
metrics = [evaluate("Logistic regression", p_lr_raw, p_lr),
           evaluate("Gradient boosting (HistGB)", p_gb_raw, p_gb),
           evaluate("Baseline: segment rate (device x source x landing)", base_te, base_te)]
R["metrics"] = metrics
R["pr_auc_random_baseline"] = float(yte.mean())
R["brier_constant_baseline"] = float(brier_score_loss(yte, np.full(len(yte), ytr.mean())))
print(pd.DataFrame(metrics).set_index("model").round(4).T)

# %% [markdown]
# ### Calibration check

# %%
cal = {}
fig, ax = plt.subplots(figsize=(5.2, 4.6))
mx = 0.16
ax.plot([0, mx], [0, mx], color=INK2, lw=1, ls="--", label="Perfect calibration")
for name, p, col in [("Logistic regression", p_lr, BLUE), ("Gradient boosting", p_gb, ORANGE)]:
    frac, mean_p = calibration_curve(yte, p, n_bins=10, strategy="quantile")
    cal[name] = {"bin_mean_predicted": mean_p.round(4).tolist(), "bin_observed": frac.round(4).tolist()}
    ax.plot(mean_p, frac, marker="o", ms=5, lw=2, color=col, label=name)
ax.set_xlim(0, mx); ax.set_ylim(0, mx)
ax.set_xlabel("Mean predicted conversion (decile of sessions)")
ax.set_ylabel("Observed conversion")
ax.set_title("Calibration on test months (Oct 2014 – Mar 2015)", fontsize=10, loc="left")
ax.legend(frameon=False, fontsize=8, loc="upper left")
fig.tight_layout(); fig.savefig(os.path.join(CHARTS, "calibration.png")); plt.close(fig)
R["calibration"] = cal
# mean absolute calibration gap across the 10 quantile bins
R["ece"] = {k: float(np.mean(np.abs(np.array(v["bin_mean_predicted"]) - np.array(v["bin_observed"]))))
            for k, v in cal.items()}
print(json.dumps(cal, indent=1))

# %% [markdown]
# ### Lift by decile

# %%
dec = pd.DataFrame({"y": yte, "p": p_lr})
dec["decile"] = pd.qcut(dec.p.rank(method="first", ascending=False), 10, labels=range(1, 11))
lift_tbl = dec.groupby("decile", observed=True).agg(sessions=("y", "size"), conv_rate=("y", "mean"))
lift_tbl["lift"] = lift_tbl.conv_rate / yte.mean()
R["lr_decile_table"] = lift_tbl.round(4).reset_index().astype({"decile": int}).to_dict("records")

fig, ax = plt.subplots(figsize=(6, 3.8))
ax.bar(lift_tbl.index.astype(int), lift_tbl.conv_rate * 100, color=BLUE, width=0.7)
ax.axhline(yte.mean() * 100, color=INK2, ls="--", lw=1)
ax.text(10.4, yte.mean() * 100 + 0.2, f"Test average {yte.mean():.1%}", ha="right", fontsize=8, color=INK2)
ax.set_xticks(range(1, 11))
ax.set_xlabel("Decile of predicted propensity (1 = highest)")
ax.set_ylabel("Observed conversion rate (%)")
ax.set_title("Logistic regression: conversion by score decile (test months)", fontsize=10, loc="left")
ax.grid(axis="x", visible=False)
fig.tight_layout(); fig.savefig(os.path.join(CHARTS, "lift_by_decile.png")); plt.close(fig)
print(lift_tbl.round(4))

# %% [markdown]
# ## 5. Top drivers: coefficients and permutation importance

# %%
names = logreg.named_steps["ohe"].get_feature_names_out()
coef = pd.DataFrame({"feature": [n.replace("cat__", "") for n in names],
                     "coef": logreg.named_steps["clf"].coef_[0]})
coef["odds_ratio"] = np.exp(coef.coef)
coef = coef.reindex(coef.coef.abs().sort_values(ascending=False).index)
R["lr_reference_levels"] = REFERENCE
R["lr_top_coefficients"] = coef.head(12).round(4).to_dict("records")
print(coef.head(15).round(3).to_string(index=False))

perm = {}
for name, model in [("Logistic regression", logreg), ("Gradient boosting", gbm)]:
    pi = permutation_importance(model, Xte, yte, scoring="average_precision", n_repeats=5,
                                random_state=SEED, n_jobs=1)
    perm[name] = (pd.DataFrame({"feature": FEATURES, "pr_auc_drop": pi.importances_mean,
                                "std": pi.importances_std})
                  .sort_values("pr_auc_drop", ascending=False))
R["permutation_importance_pr_auc_drop"] = {k: v.round(4).to_dict("records") for k, v in perm.items()}
for k, v in perm.items():
    print(k); print(v.round(4).to_string(index=False))

fig, axes = plt.subplots(1, 2, figsize=(9, 3.8), sharey=True)
order_feats = perm["Logistic regression"].feature.tolist()[::-1]
for ax, (name, col) in zip(axes, [("Logistic regression", BLUE), ("Gradient boosting", ORANGE)]):
    v = perm[name].set_index("feature").loc[order_feats]
    ax.barh(order_feats, v.pr_auc_drop, xerr=v["std"], color=col, height=0.6, ecolor=INK2)
    ax.set_title(name, fontsize=10, loc="left"); ax.set_xlabel("Drop in PR-AUC when shuffled")
    ax.grid(axis="y", visible=False)
fig.suptitle("Permutation importance on test months", x=0.01, ha="left", fontsize=11)
fig.tight_layout(); fig.savefig(os.path.join(CHARTS, "permutation_importance.png")); plt.close(fig)

top_c = coef.head(12).iloc[::-1]
fig, ax = plt.subplots(figsize=(6.5, 4.2))
ax.barh(top_c.feature, top_c.coef, color=[BLUE if c > 0 else ORANGE for c in top_c.coef], height=0.6)
ax.axvline(0, color=INK2, lw=1)
ax.set_xlabel("Logistic regression coefficient (log-odds vs reference level)")
ax.set_title("Largest coefficients (blue raises, orange lowers conversion)", fontsize=10, loc="left")
ax.grid(axis="y", visible=False)
fig.tight_layout(); fig.savefig(os.path.join(CHARTS, "top_coefficients.png")); plt.close(fig)

# %% [markdown]
# ## 6. Product angle: predicted conversion by device x landing page x traffic source

# %%
test = test.assign(p_lr=p_lr, p_gb=p_gb)
seg = (test.groupby(["device", "landing_page", "traffic_source"])
       .agg(sessions=("converted", "size"), observed_cr=("converted", "mean"),
            predicted_cr_lr=("p_lr", "mean"), predicted_cr_gb=("p_gb", "mean"))
       .query("sessions >= 300").sort_values("sessions", ascending=False))
R["segments_test"] = seg.round(4).reset_index().to_dict("records")
print(seg.round(4).to_string())

dl = (test.groupby(["device", "landing_page"])
      .agg(sessions=("converted", "size"), observed=("converted", "mean"), predicted=("p_lr", "mean"))
      .query("sessions >= 300").reset_index())
dl["label"] = dl.device + "  " + dl.landing_page
dl = dl.sort_values("observed")
fig, ax = plt.subplots(figsize=(6.5, 3.6))
y = np.arange(len(dl))
ax.barh(y - 0.18, dl.observed * 100, height=0.34, color=BLUE, label="Observed")
ax.barh(y + 0.18, dl.predicted * 100, height=0.34, color=ORANGE, label="Predicted (logistic, corrected)")
for yi, (o, n) in enumerate(zip(dl.observed, dl.sessions)):
    ax.text(o * 100 + 0.15, yi - 0.18, f"{o:.1%}  (n={n:,})", va="center", fontsize=7, color=INK2)
ax.set_yticks(y); ax.set_yticklabels(dl.label)
ax.set_xlabel("Conversion rate (%)")
ax.set_title("Conversion by device × landing page (test months)", fontsize=10, loc="left")
ax.legend(frameon=False, fontsize=8, loc="lower right"); ax.grid(axis="y", visible=False)
fig.tight_layout(); fig.savefig(os.path.join(CHARTS, "device_landing_conversion.png")); plt.close(fig)

# %% [markdown]
# ## 7. Which fix is worth more: mobile experience or landing page?
#
# Counterfactuals on the test window, scored with the logistic regression:
# * **Mobile fix (ceiling):** every mobile session is re-scored as desktop, and the
#   mobile paid lander (/lander-3) is mapped to the desktop paid lander that ran in the same
#   window (/lander-5). Everything else (source, campaign, hour, ...) is kept. This asks
#   "what if mobile visitors converted like comparable desktop visitors".
# * **Landing-page fix (ceiling):** device is kept; every session on a paid lander is moved
#   to the best-scoring lander that device actually used in the data (desktop: /lander-5,
#   mobile: /lander-3). /home sessions (organic, direct, brand) are left alone.
#
# Conversion rose over time, so a model trained on earlier months could mis-state the level
# in the test window. For revenue we therefore re-level the model with a single intercept
# shift so its mean matches the test window's observed rate (a descriptive step, done after
# evaluation), and report the un-shifted figure too. AOV is the test window's observed average order value.

# %%
def lr_logit(X):
    p = corrected_proba(logreg, X)
    return np.log(p / (1 - p))


test_orders = orders[orders.website_session_id.isin(test.website_session_id)]
AOV = float(test_orders.price_usd.mean())
base_logit = lr_logit(Xte)

# one-parameter intercept shift so mean prediction = observed test conversion rate
lo, hi = -3.0, 3.0
for _ in range(60):
    mid = (lo + hi) / 2
    if (1 / (1 + np.exp(-(base_logit + mid)))).mean() < yte.mean():
        lo = mid
    else:
        hi = mid
SHIFT = (lo + hi) / 2


def scenario(Xcf, mask):
    out = {}
    for label, s in [("releveled", SHIFT), ("model_as_is", 0.0)]:
        p0 = 1 / (1 + np.exp(-(base_logit + s)))
        p1 = 1 / (1 + np.exp(-(lr_logit(Xcf) + s)))
        extra = float((p1 - p0)[mask].sum())
        out[label] = {"extra_orders": extra, "extra_revenue": extra * AOV,
                      "extra_revenue_annualised": extra * AOV * 365 / R["split"]["test_days"]}
    out["sessions_affected"] = int(mask.sum())
    return out


# Mobile fix
Xm = Xte.copy()
mob = (Xm.device == "mobile").values
Xm.loc[mob, "device"] = "desktop"
Xm.loc[mob & (Xm.landing_page == "/lander-3").values, "landing_page"] = "/lander-5"
mobile_fix = scenario(Xm, mob)

# Landing-page fix: best lander per device among landers that device actually used (full data)
lander_rows = df[df.landing_page.str.startswith("/lander")]
used = lander_rows.groupby("device").landing_page.unique().to_dict()
coef_map = dict(zip(coef.feature, coef.coef))
best = {d: max(pages, key=lambda pg: coef_map.get(f"landing_page_{pg}", 0.0)) for d, pages in used.items()}
Xl = Xte.copy()
lp_mask = np.zeros(len(Xl), bool)
for d, pg in best.items():
    m = ((Xl.device == d) & Xl.landing_page.str.startswith("/lander") & (Xl.landing_page != pg)).values
    Xl.loc[m, "landing_page"] = pg
    lp_mask |= m
landing_fix = scenario(Xl, lp_mask)

# Sensitivity: same mobile counterfactual scored with gradient boosting (re-levelled the same way)
gb_logit0 = np.log(p_gb / (1 - p_gb))
lo, hi = -3.0, 3.0
for _ in range(60):
    mid = (lo + hi) / 2
    lo, hi = (mid, hi) if (1 / (1 + np.exp(-(gb_logit0 + mid)))).mean() < yte.mean() else (lo, mid)
gshift = (lo + hi) / 2
pg_m = corrected_proba(gbm, Xm)
gb_mobile_extra = float((1 / (1 + np.exp(-(np.log(pg_m / (1 - pg_m)) + gshift)))
                         - 1 / (1 + np.exp(-(gb_logit0 + gshift))))[mob].sum())

R["revenue"] = {
    "aov_test_window": AOV, "intercept_shift": float(SHIFT),
    "best_lander_by_device": best,
    "mobile_fix": mobile_fix, "landing_page_fix": landing_fix,
    "mobile_fix_gbm_releveled_extra_orders": gb_mobile_extra,
    "mobile_fix_gbm_releveled_extra_revenue": gb_mobile_extra * AOV,
    "mobile_vs_landing_ratio_releveled": mobile_fix["releveled"]["extra_revenue"]
    / max(landing_fix["releveled"]["extra_revenue"], 1e-9),
}
print(json.dumps(R["revenue"], indent=1))

# %% [markdown]
# ### Reconcile with the SQL project's $282K mobile gap and ~$322K funnel figure

# %%
gn = df[(df.utm_source == "gsearch") & (df.utm_campaign == "nonbrand")]
by_dev = gn.groupby("device").converted.agg(["size", "mean"])
m_sess = int(by_dev.loc["mobile", "size"])
cr_d, cr_m = by_dev.loc["desktop", "mean"], by_dev.loc["mobile", "mean"]
aov_all = float(orders.price_usd.mean())
sql_repro = m_sess * (round(cr_d * 100, 2) - round(cr_m * 100, 2)) / 100 * 64  # exactly the SQL steps
same_method_true_aov = m_sess * (cr_d - cr_m) * aov_all

# Naive SQL-style gap on the TEST window, all mobile traffic (desktop rate applied to mobile)
td = test.groupby("device").converted.agg(["size", "mean"])
naive_test_gap = td.loc["mobile", "size"] * (td.loc["desktop", "mean"] - td.loc["mobile", "mean"]) * AOV

# ~$322K figure: +5pp product-page -> cart on Mr. Fuzzy sessions. Re-derive it from the data.
pv_sess = pageviews.groupby("website_session_id").pageview_url.agg(set)
fuzzy_sessions = int(pv_sess.apply(lambda s: "/the-original-mr-fuzzy" in s).sum())
cart_sessions = int(pv_sess.apply(lambda s: "/cart" in s).sum())
cart_to_order = R["n_orders"] / cart_sessions
extra_carts = fuzzy_sessions * 0.05
funnel_repro = extra_carts * cart_to_order * aov_all

R["reconciliation"] = {
    "sql_mobile_sessions_gsearch_nonbrand": m_sess,
    "desktop_cr_gsearch_nonbrand": float(cr_d), "mobile_cr_gsearch_nonbrand": float(cr_m),
    "sql_method_reproduced_usd": float(sql_repro),
    "sql_method_with_actual_aov_usd": float(same_method_true_aov), "actual_aov_all_orders": aov_all,
    "naive_gap_test_window_all_mobile_usd": float(naive_test_gap),
    "mr_fuzzy_page_sessions": fuzzy_sessions, "cart_sessions": cart_sessions,
    "cart_to_order_rate": float(cart_to_order),
    "funnel_5pp_extra_carts": float(extra_carts),
    "funnel_5pp_revenue_if_carts_convert_at_observed_rate_usd": float(funnel_repro),
    "funnel_5pp_revenue_if_every_extra_cart_orders_usd": float(extra_carts * aov_all),
}
print(json.dumps(R["reconciliation"], indent=1))

# %%
fig, ax = plt.subplots(figsize=(6.8, 3.4))
bars = [
    ("Landing-page fix\n(model, test window)", landing_fix["releveled"]["extra_revenue"]),
    ("Mobile fix\n(model, test window)", mobile_fix["releveled"]["extra_revenue"]),
    ("Mobile gap, desktop rate on mobile\n(naive, test window)", naive_test_gap),
    ("SQL project mobile gap\n(gsearch nonbrand, 3 years)", sql_repro),
]
ax.barh([b[0] for b in bars], [b[1] / 1000 for b in bars], color=[BLUE, BLUE, INK2, INK2], height=0.6)
for i, (_, v) in enumerate(bars):
    ax.text(v / 1000 + 3, i, f"${v / 1000:,.0f}K", va="center", fontsize=8)
ax.set_xlabel("Estimated extra revenue (USD thousands)")
ax.set_title("Revenue impact: mobile fix vs landing-page fix", fontsize=10, loc="left")
ax.grid(axis="y", visible=False); ax.set_xlim(0, max(b[1] for b in bars) / 1000 * 1.2)
fig.tight_layout(); fig.savefig(os.path.join(CHARTS, "revenue_impact.png")); plt.close(fig)

# %% [markdown]
# ## 8. Save results

# %%
with open(os.path.join(OUT, "results.json"), "w") as f:
    json.dump(R, f, indent=2, default=str)

m_lr, m_gb, m_bs = R["metrics"]
rv, rc, sp = R["revenue"], R["reconciliation"], R["split"]
lines = [
    "# Results summary (generated by conversion_model.py; every number below comes from this run)",
    "",
    f"- Sessions: {R['n_sessions']:,}; orders: {R['n_orders']:,}; overall conversion {R['overall_conversion_rate']:.2%}",
    f"- Train: {sp['train_period']} ({sp['train_sessions']:,} sessions, {sp['train_conversion_rate']:.2%} conversion)",
    f"- Test: {sp['test_period']} ({sp['test_sessions']:,} sessions, {sp['test_conversion_rate']:.2%} conversion, {sp['test_days']} days)",
    "",
    "## Model performance on the test months",
    "",
    "| Model | ROC-AUC | PR-AUC | Top-decile conv. | Top-decile lift | Share of orders in top decile | Brier (corrected) |",
    "|---|---|---|---|---|---|---|",
]
for m in R["metrics"]:
    lines.append(f"| {m['model']} | {m['roc_auc']:.3f} | {m['pr_auc']:.3f} | {m['top_decile_conversion_rate']:.2%} | "
                 f"{m['top_decile_lift']:.2f}x | {m['top_decile_share_of_orders']:.1%} | {m['brier_corrected']:.4f} |")
lines += [
    "",
    f"- PR-AUC of a random ranking = test conversion rate = {R['pr_auc_random_baseline']:.3f}. "
    f"Brier of a constant train-rate prediction = {R['brier_constant_baseline']:.4f}.",
    f"- Calibration: class-weighted raw scores average {m_lr['mean_raw_predicted']:.3f} (LR), far above the real rate, as expected "
    f"from re-weighting. After the prior correction they average {m_lr['mean_corrected_predicted']:.4f} (LR) / "
    f"{m_gb['mean_corrected_predicted']:.4f} (GB) vs an observed {sp['test_conversion_rate']:.4f}. "
    f"Mean absolute gap between predicted and observed across 10 quantile bins: LR {R['ece']['Logistic regression']:.4f}, "
    f"GB {R['ece']['Gradient boosting']:.4f} (see charts/calibration.png).",
    "",
    "## Top drivers",
    "",
    "Logistic regression, largest coefficients (reference: " + ", ".join(f"{k}={v}" for k, v in REFERENCE.items()) + "):",
    "",
]
for r_ in R["lr_top_coefficients"][:8]:
    lines.append(f"- {r_['feature']}: coef {r_['coef']:+.3f} (odds ratio {r_['odds_ratio']:.2f})")
lines += ["", "Permutation importance (drop in PR-AUC, test months):", ""]
for k, v in R["permutation_importance_pr_auc_drop"].items():
    lines.append(f"- {k}: " + ", ".join(f"{d['feature']} {d['pr_auc_drop']:.4f}" for d in v))
lines += [
    "",
    "## Mobile fix vs landing-page fix (test window, logistic regression, re-levelled)",
    "",
    f"- AOV (test window): ${rv['aov_test_window']:.2f}",
    f"- Mobile fix: {rv['mobile_fix']['sessions_affected']:,} sessions, +{rv['mobile_fix']['releveled']['extra_orders']:,.0f} orders, "
    f"+${rv['mobile_fix']['releveled']['extra_revenue']:,.0f} over {sp['test_days']} days "
    f"(~${rv['mobile_fix']['releveled']['extra_revenue_annualised']:,.0f}/yr annualised; model as-is without re-levelling: "
    f"+${rv['mobile_fix']['model_as_is']['extra_revenue']:,.0f})",
    f"- Same mobile counterfactual scored by gradient boosting: +{rv['mobile_fix_gbm_releveled_extra_orders']:,.0f} orders, "
    f"+${rv['mobile_fix_gbm_releveled_extra_revenue']:,.0f}",
    f"- Landing-page fix (best lander per device: {rv['best_lander_by_device']}): {rv['landing_page_fix']['sessions_affected']:,} sessions, "
    f"+{rv['landing_page_fix']['releveled']['extra_orders']:,.0f} orders, +${rv['landing_page_fix']['releveled']['extra_revenue']:,.0f} "
    f"(~${rv['landing_page_fix']['releveled']['extra_revenue_annualised']:,.0f}/yr; as-is +${rv['landing_page_fix']['model_as_is']['extra_revenue']:,.0f})",
    f"- Mobile fix is worth {rv['mobile_vs_landing_ratio_releveled']:.1f}x the landing-page fix.",
    "",
    "## Reconciliation with the SQL project",
    "",
    f"- SQL $282K reproduced (report says $282,404; difference is rounding): {rc['sql_mobile_sessions_gsearch_nonbrand']:,} gsearch-nonbrand mobile sessions x "
    f"({rc['desktop_cr_gsearch_nonbrand']:.2%} - {rc['mobile_cr_gsearch_nonbrand']:.2%}) x $64 = ${rc['sql_method_reproduced_usd']:,.0f} "
    f"(3 years, assumed $64 AOV). With the actual AOV ${rc['actual_aov_all_orders']:.2f}: ${rc['sql_method_with_actual_aov_usd']:,.0f}.",
    f"- Naive desktop-rate-on-mobile gap in the test window (all mobile traffic): ${rc['naive_gap_test_window_all_mobile_usd']:,.0f}.",
    f"- ~$322K funnel figure: +5pp cart rate on {rc['mr_fuzzy_page_sessions']:,} Mr. Fuzzy sessions = {rc['funnel_5pp_extra_carts']:,.0f} extra carts. "
    f"At the observed cart-to-order rate ({rc['cart_to_order_rate']:.1%}) and AOV that is ${rc['funnel_5pp_revenue_if_carts_convert_at_observed_rate_usd']:,.0f}; "
    f"even if every extra cart became an order it is ${rc['funnel_5pp_revenue_if_every_extra_cart_orders_usd']:,.0f}. "
    "It is a product-page-to-cart fix, which this start-of-session model cannot evaluate (those pageviews are excluded as leakage).",
]
with open(os.path.join(OUT, "results_summary.md"), "w") as f:
    f.write("\n".join(lines) + "\n")
print("\n".join(lines))
