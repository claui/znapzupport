# znapzupport

**znapzupport** is a collection of CLI helpers to enhance the awesome backup tool [ZnapZend](http://www.znapzend.org).


## Warning

**This is alpha-quality software.** If you don’t know what this means, do not use any of the scripts in this collection.

If you do use znapzupport, be advised that it is largely untested.


## System requirements

To use znapzupport, you need:

- OS&nbsp;X 10.11 El Capitan, macOS 10.12 Sierra, or a later macOS version;

- the [open source port of OpenZFS for macOS](https://openzfsonosx.org); and

- znapzend version 0.17.0 or newer.


## Installation

1. Make sure you have [Homebrew](https://brew.sh) installed.

2. Run `brew tap claui/public` if you haven’t already done so.

3. Run:

```
brew install znapzupport
```


# The commands

The `znapzupport` suite consists of the following commands:

|   Command   |   Purpose   |
|:----------- |:----------- |
| `znaphodl`  | Protect load-bearing snapshots from being removed by ZnapZend |
| `znaphodlz` | Print a list of rolling hold tags |
| `znaplizt`  | Print a list of home and backup datasets |
| `zpoolz`    | Print a list of zpools |


## znaphodl

While I love ZnapZend almost as much as I love ZFS, it does not try to solve the following problem:

1. I have a number of USB media.

2. For backup purposes, I use ZnapZend to incrementally `zfs send` my laptop’s home pool (SRC) to the USB media (DST).

3. I keep those drives at multiple locations for redundancy. I visit some of those DSTs almost daily, while other DSTs don’t get updated for weeks.

4. Due to space constraints, I have set up ZnapZend to keep a fairly small number of snapshots on my laptop (SRC), while the backup drives (DSTs) are configured to hold their snapshots for longer periods.

5. Regardless, my goal is that each DST gets to keep a long trail, and should always be ready to receive incremental snapshots, even if not visited for weeks or months.

To receive incremental snapshots, every DST needs to keep a common snapshot relative to SRC, which I’ll call a **load-bearing snapshot** for the purpose of this discussion.

The issue I have with ZnapZend is that its automatic cleanup feature does not discriminate between normal snapshots and load-bearing snapshots on my SRC; it deletes either as soon as it thinks its time has come. Because of \#4 and \#5, it often happened that one or more of my DSTs stop accepting snapshots because ZnapZend removed a load-bearing snapshot from my SRC.

`znaphodl` is a **post-send handler for ZnapZend** designed to solve this issue by setting a rolling hold tag on load-bearing snapshots.


### Wait, I didn’t catch that.

I use ZnapZend to back up my zpool. Whenever I wait too long between backups, ZnapZend deletes my snapshots. Sometimes that breaks my backup chain.

I then have to delete all snapshots from my external media and start over, which is not what I want.

This is why I wrote `znaphodl`, a tool which protects load-bearing snapshots from being deleted.


### How znaphodl works

When used as a post-send handler for a `DST` entry in ZnapZend, `znaphodl` causes the `SRC` dataset to hold onto at least one snapshot which has a twin sibling in `DST`.

`znaphodl` accomplishes this by calculating the latest load-bearing snapshot for each DST. It then instructs ZFS to `hold` onto that load-bearing snapshot, which means ZnapZend won’t be able to delete it. `znaphodl` uses a distinct _rolling tag_ for each corresponding `DST` dataset. This ensures that the tag will be unique to each `DST` dataset.

Whenever `znaphodl` detects a new load-bearing snapshot appears on the `DST` dataset, it moves the rolling tag to that new snapshot. The snapshot previously tagged will then become eligible for cleanup, and ZnapZend will be able to delete it from `SRC` as soon as its configuration allows.


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

The `znaphodl` command does not support any command-line options at this time.


## znaphodlz

`znaphodlz` prints a list of rolling hold tags (see `znaphodl`). The list is grouped by the associated `SRC` dataset.

`znaphodlz` currently does not support command-line options.


## znaplizt

`znaplizt` displays a list of **home and backup datasets.**

A **home dataset** is a ZFS dataset which has a `cat.claudi:id` property (dubbed _dataset ID_) with a non-null value.

A **backup dataset** is associated to a specific home dataset; it is defined as a ZFS dataset named `${pool}/backup/${dataset_id}/${username}`, with:

- `${pool}` being the zpool name;

- `${dataset_id}` being the dataset ID of the home dataset; and

- `${username}` being the name of the current user.

The `znaplizt` command only shows imported datasets.

For each home or backup dataset, the command also lists its associated snapshots.


### Command-line options

The `znaplizt` command supports the following command-line options:

- `-b` List only backup datasets. Cannot be used together with `-h`.

- `-h` List only home datasets. Not compatible with the `-b` option.

- `-m dataset_id` List only a specific home dataset, whose `cat.claudi:id` is equal to the given `dataset_id`.

- `-v` Be more verbose.


## zpoolz

`zpoolz` prints the name of each zpool that is currently imported.

It does not support any command-line options at this time.


# Legal notice

This suite of programs is in no way affiliated with, nor has it any connection to, nor is it being endorsed by OETIKER+PARTNER, nor by any of its websites or subsidiaries, nor by any of the ZnapZend authors.


# License

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
