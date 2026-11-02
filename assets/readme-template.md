# {{App name}}

<p>
  <a href="{{live url}}"><img alt="live: online" src="docs/assets/badge-live.svg"></a>
  <a href="{{repo}}/actions/workflows/test.yml"><img alt="tests: {{N}} passing" src="docs/assets/badge-tests.svg"></a>
  <a href="{{repo}}/actions/workflows/build-apps.yml"><img alt="build: green" src="docs/assets/badge-build.svg"></a>
  <a href="LICENSE"><img alt="licence: {{licence}}" src="docs/assets/badge-licence.svg"></a>
  <img alt="offline: no network" src="docs/assets/badge-offline.svg">
  <img alt="deps: {{n}} runtime" src="docs/assets/badge-deps.svg">
</p>

**{{One sentence: what it is, in the owner's own terms.}}**

**[Open the app →]({{live url}}/play/)** · [Landing page]({{live url}}/) · [The rule](#the-rule) · [Support](#support)

<!-- shot:start -->

![Screenshot](docs/shot.png)

<!-- shot:end -->

{{One short paragraph: offline? accounts? server? build step? dependencies?}}

## What it does

{{Two or three sentences, then the mechanic as a table or a short list.}}

| | |
|---|---|
| {{the numbers that matter}} | **{{n}}** |

## What it must not do, and does not

- {{the restraints, stated as rules rather than hopes}}

## Run it

```bash
node test-node.js
```

## Platforms

Windows, Linux and Android. There is no macOS or iOS build — the app is a web page, and the same
page is the product on all three.

## Layout

```
docs/index.html         the landing page
docs/play/index.html    the app
docs/assets/            screenshots, generated badges, the UPI QR, the portrait
```

## Support

<img src="docs/assets/support-portrait.jpg" width="72" height="72" alt="Dr. Sohil Momin" align="left" style="border-radius:50%;margin-right:1rem">

Free, offline, accountless — and staying that way. If it earned its keep:

| | |
|---|---|
| UPI (India) | `drsohilboi@ybl` — payee Dr. Sohil Momin, open amount, or scan [the QR](docs/assets/upi-qr.svg) |
| Ko-fi | [ko-fi.com/matneo](https://ko-fi.com/matneo) |
| PayPal | [paypal.me/drsohilmomin](https://paypal.me/drsohilmomin?locale.x=en_GB&country.x=IN) |
| My books | [Amazon author store](https://www.amazon.com/stores/author/B08ZT331LY/allbooks?ccs_id=aed72b9f-71d9-41dc-adee-e9368a317acc) |
| More apps | [drsamonline.github.io](https://drsamonline.github.io/) |
| Email | [sohilmomin2000@gmail.com](mailto:sohilmomin2000@gmail.com) |

Nothing is gated behind it: no accounts, no tracking, no network requests.

## Licence

{{licence}} — see `LICENSE`.
