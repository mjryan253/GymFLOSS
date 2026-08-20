# Third-party notices

openGym — Copyright (C) 2026 Duarte Santos.
openGym's own code is licensed under the **GNU AGPL v3.0** (see [LICENSE](LICENSE)).

## Provenance

This repository is a fork. openGym was written by **Duarte Santos**
(`github.com/DuarteSantos8`), whose repository, website and published images are no longer
reachable; the only surviving public copy was a re-upload by a third party, from which this
fork descends. Original authorship and copyright are unchanged and are asserted above.
Modifications made since the fork are © their respective contributors under the same license.
See `MAINTAINERS.md` for the full chain of custody.

## App store exception

As an additional permission under section 7 of the AGPL v3.0, the copyright holder permits
distribution of the openGym mobile application through app store platforms (such as the
Apple App Store and Google Play) whose terms of service would otherwise be incompatible
with the AGPL, provided the corresponding source code remains available under the AGPL at
the project repository. This permission applies to the distribution channel only and does
not otherwise limit the license.

## Body diagram geometry

The muscle outlines the body maps are drawn from (`frontend/src/lib/body-paths.js`) are derived
from [**MuscleMap**](https://github.com/melihcolpan/MuscleMap) by Melih Colpan, used under the
**MIT License** and reproduced below. MuscleMap ships its path data as Swift source rather than
`.svg` files; the paths were converted to a JSON module, its sub-group shapes were dropped, and
nothing else about the artwork was changed.

```
MIT License

Copyright (c) 2026 Melih Colpan

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Exercise data & media

The exercise names, instructions (English in `frontend/src/lib/exercises-data.js`, other
languages in `frontend/src/instr/`, regenerated via `scripts/build-instructions.mjs`), images
and animations (fetched into `media/` at build time) come from
[**hasaneyldrm/exercises-dataset**](https://github.com/hasaneyldrm/exercises-dataset)
and are **not** covered by openGym's AGPL license — they remain under that dataset's own terms.
That dataset is MIT for its code, data and instruction text, but its **media carries separate
terms**:

> The exercise images and animations are **© [Gym visual](https://gymvisual.com/)**,
> redistributed by the upstream dataset at 180×180 with permission and with the attribution
> `© Gym visual — https://gymvisual.com/` required to be kept intact. That permission was
> granted to the dataset and does not extend to downstream forks. Reuse is governed by
> [Gym visual's Terms & Conditions](https://gymvisual.com/content/3-terms-and-conditions-of-use);
> obtain your own license there before reusing the media.

Accordingly, **the media files are not distributed in this repository**. `media/` is
gitignored, and the images and GIFs are fetched from the upstream source at runtime — by the
`media` service in `docker-compose.yml`, by `scripts/fetch-media.sh`, or from the jsDelivr
mirror in the mobile and demo builds. Do not commit them, and do not include them in a release
artifact or a published container image.
