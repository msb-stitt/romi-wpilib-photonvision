# Requirements

MUST, MUST NOT, SHOULD, SHOULD NOT and MAY carry their
[RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) meanings here.

## `upstream.provenance` — Configure PhotonVision and WPILib; do not change them

PhotonVision and WPILib are upstream projects this one installs and configures.

- An upstream file copied into a target image MUST keep its licence header.
- An upstream definition MUST NOT be edited in place; generated configuration changes it instead.
- A target image MUST record the upstream version of each project it was built from.
