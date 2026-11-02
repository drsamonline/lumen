#!/usr/bin/env python3
"""Draw the UPI payment QR as a local SVG, committed next to the page.

Same rule as the badges: a page that loads nothing from the network must not
fetch its own donation QR from an image service either. The QR encodes a
`upi://pay` URI, so any UPI app in India can scan it; the VPA is also printed
as text on the page for anyone reading on a desktop.

  python3 tools/support_qr.py                       # -> docs/assets/upi-qr.svg
  python3 tools/support_qr.py --upi x@y --payee "Name" --out docs/assets/upi-qr.svg

The intent is always open-amount — there is no --amount flag, on purpose: a
prefilled sum or a row of suggested tiers turns a thank-you into a price list.

Requires `segno` (pip install segno). Build-time only; nothing is added to the
app's runtime.
"""
import argparse
import json
import os
import sys
import urllib.parse

DEFAULTS = {
    "upi": "drsohilboi@ybl",
    "payee": "Dr. Sohil Momin",
    "currency": "INR",
    "out": os.path.join("docs", "assets", "upi-qr.svg"),
}


def upi_uri(pa, pn, cu="INR"):
    """Build the UPI intent URI. Percent-encode, never hand-concatenate.

    No `am=` parameter, deliberately: the block asks for an open amount.
    """
    params = {"pa": pa, "pn": pn, "cu": cu}
    return "upi://pay?" + urllib.parse.urlencode(params, quote_via=urllib.parse.quote)


def write_qr(out, upi=None, payee=None, currency=None, scale=6):
    """Write the QR to `out` and return (path, uri).

    Raises RuntimeError when segno is missing, so a caller can report it instead
    of dying mid-run.
    """
    upi = upi or DEFAULTS["upi"]
    payee = payee or DEFAULTS["payee"]
    currency = currency or DEFAULTS["currency"]
    uri = upi_uri(upi, payee, currency)

    try:
        import segno
    except ImportError:
        raise RuntimeError("segno is not installed (pip install segno)")

    os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
    segno.make(uri, error="m").save(
        out,
        scale=scale,
        border=2,
        dark="#0b0b0b",
        light="#ffffff",
        xmldecl=True,
        svgversion=1.1,
        title="UPI: %s" % upi,
        desc="Scan with any UPI app to pay %s" % payee,
    )
    return out, uri


def main():
    ap = argparse.ArgumentParser(description="Generate the UPI payment QR as SVG.")
    ap.add_argument("--upi", help="VPA, e.g. name@bank")
    ap.add_argument("--payee", help="payee name shown in the payer's UPI app")
    ap.add_argument("--currency", help="currency code, default INR")
    ap.add_argument("--out", help="output path, default docs/assets/upi-qr.svg")
    ap.add_argument("--scale", type=int, default=6, help="module size in px, default 6")
    ap.add_argument("--config", help="JSON file with upi/payee/currency keys")
    args = ap.parse_args()

    cfg = dict(DEFAULTS)
    if args.config and os.path.exists(args.config):
        with open(args.config, encoding="utf-8") as fh:
            cfg.update(json.load(fh))
    for key in ("upi", "payee", "currency", "out"):
        val = getattr(args, key, None)
        if val:
            cfg[key] = val

    try:
        out, uri = write_qr(cfg["out"], cfg["upi"], cfg["payee"], cfg["currency"], args.scale)
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        print("The page still works without it — keep the VPA as text and leave the QR slot "
              "filled by a previously generated file.", file=sys.stderr)
        return 2

    print("wrote", out)
    print("uri ", uri)
    print("keep the QR on a white tile in dark mode — an inverted QR will not scan")
    return 0


if __name__ == "__main__":
    sys.exit(main())
