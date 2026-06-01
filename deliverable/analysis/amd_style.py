"""
amd_style.py — the one locked design system, shared by every chart (and mirrored by the
dashboard CSS + Marp theme). AMD red dominant on near-black (dark) or paper (light),
steel-blue data contrast, teal status. JetBrains Mono throughout (instrument aesthetic).
"""
from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.font_manager as fm
import matplotlib.pyplot as plt

# ---- palette ----
RED      = "#ED1C24"   # AMD red (dominant)
RED_BR   = "#FF3B30"
RED_DP   = "#7E0F15"
STEEL    = "#5AA9E6"   # cool data contrast
STEEL_DP = "#2E6CA0"
TEAL     = "#2DD4BF"   # positive / status (sparing)
AMBER_X  = None        # intentionally no yellow

DARK = dict(bg="#0A0A0C", panel="#141418", grid="#23232B", ink="#F2F3F5",
            ink_dim="#9A9AA6", spine="#2C2C35")
LIGHT = dict(bg="#FFFFFF", panel="#FBFAF7", grid="#E7E5E0", ink="#16171B",
             ink_dim="#6A6C72", spine="#D9D5CC")

# categorical ramp (no yellow, no purple): red, steel, teal, slate, deep-red, light-steel
CATEG = [RED, STEEL, TEAL, "#8A8F9A", RED_DP, "#9CC8EF"]

_FONTS = Path(__file__).resolve().parent.parent / "assets" / "fonts"
_MONO = "DejaVu Sans Mono"
for ttf in _FONTS.glob("*.ttf"):
    try:
        fm.fontManager.addfont(str(ttf))
    except Exception:
        pass
if any(_FONTS.glob("JetBrainsMono*.ttf")):
    _MONO = "JetBrains Mono"


def theme(name="dark"):
    """Apply rcParams for the given skin and return its color dict."""
    c = DARK if name == "dark" else LIGHT
    plt.rcParams.update({
        "figure.facecolor": c["bg"], "axes.facecolor": c["bg"],
        "savefig.facecolor": c["bg"], "savefig.edgecolor": c["bg"],
        "font.family": _MONO, "font.size": 12,
        "text.color": c["ink"], "axes.labelcolor": c["ink"],
        "axes.edgecolor": c["spine"], "axes.titlecolor": c["ink"],
        "xtick.color": c["ink_dim"], "ytick.color": c["ink_dim"],
        "axes.grid": True, "grid.color": c["grid"], "grid.linewidth": 0.8,
        "axes.axisbelow": True, "axes.spines.top": False, "axes.spines.right": False,
        "figure.dpi": 200, "savefig.dpi": 200, "savefig.bbox": "tight",
        "savefig.pad_inches": 0.25,
    })
    return c


def save(fig, name, themename):
    out = Path(__file__).resolve().parent.parent / "assets" / themename
    out.mkdir(parents=True, exist_ok=True)
    fig.savefig(out / f"{name}.png")
    plt.close(fig)
    return out / f"{name}.png"
