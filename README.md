# znapzupport

**znapzupport** is a collection of CLI helpers to enhance the awesome backup tool [ZnapZend](http://www.znapzend.org).


## Warning

**This is alpha-quality software.** If you don’t know what this means, do not use any of the scripts in this collection.

If you do use znapzupport, be advised that it is largely untested.


## System requirements

- To use znapzupport, you need OS&nbsp;X 10.11 El Capitan, macOS 10.12 Sierra, or a later macOS version.

- You also need znapzend version 0.17.0 or newer.


## Installation

1. Make sure you have [Homebrew](https://brew.sh) installed.

2. Run `brew tap claui/public` if you haven’t already done so.

3. Run:

```
brew install znapzupport
```


## znaphodl

At this time, znapzupport ships with just a single program, `znaphodl`. It is a **post-send handler for ZnapZend** designed to solve a common issue with the automatic cleanup feature built into ZnapZend.


### Why znaphodl?

In my opinion, ZnapZend’s automatic cleanup feature does a very good job; however, for my personal use case (i. e. sending my laptop’s local ZFS snapshots to an external storage for backup), ZnapZend fails to take into account that at least one common snapshot needs to remain in both the source and the destination dataset.

In other words: whenever I wait too long with my backup, the entire chain of snapshots breaks, and cannot be used anymore for incremental backups. I have to delete all snapshots from my external media and start over.

This is why I wrote `znaphodl`.


## How znaphodl works

When used as a post-send handler in a `DST` entry in ZnapZend, `znaphodl` causes the `SRC` dataset to hold onto at least one snapshot which is also present in the `DST` entry.

`znaphodl` accomplishes this by calculating the latest common snapshot; then `znaphodl` instructs the `SRC` dataset to `zfs hold` onto that common snapshot. `znaphodl` uses a _rolling ZFS hold tag,_ whose name is derived from the corresponding `DST` dataset. This ensures that the ZFS hold tag is unique to each `DST` dataset.

Whenever a new common snapshot appears on the `DST` dataset, `znaphodl` moves the rolling tag to that new common snapshot. The previously tagged snapshot becomes then eligible for cleanup on the `SRC` dataset (as soon as the ZnapZend configuration allows that).


### Using znaphodl

1. Create a `znapzendzetup` plan, or edit your existing plan.

2. You typically want to have one or more `DST` entries in your plan.

3. Decide for which of your `DST` entries you want to force your `SRC` dataset to hold onto at least one common snapshot at all times. You can choose more than one `DST` entries for this if you want.

4. Add the following expression as a `post-send-command`:

    ```
    znaphodl pool/tank mydstkey
    ```

    where `pool/tank` is your `SRC` dataset, and `mydstkey` is your `DST` key.

    Do not forget to enclose your entire post-send-command in quotes.

Example:

```
sudo znapzendzetup create \
  SRC '36h=>1h,15d=>1d,4w=>1w' \
    pool/tank \
  DST:mydstkey '1w=>1h,30d=>1d,8w=>1w,1y=>1mon,5y=>1y' \
    ocean/big/backup \
    off 'znaphodl pool/tank mydstkey'
```


## Legal notice

This suite of programs is in no way affiliated with, nor has it any connection to, nor is it being endorsed by OETIKER+PARTNER, nor by any of its websites or subsidiaries, nor by any of the ZnapZend authors.


## License

Copyright (c) 2018 Claudia <clau@tiqua.de>

Permission to use, copy, modify, and/or distribute this software for
any purpose with or without fee is hereby granted, provided that the
above copyright notice and this permission notice appear in all
copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL
WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE
AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL
DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR
PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER
TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
PERFORMANCE OF THIS SOFTWARE.
