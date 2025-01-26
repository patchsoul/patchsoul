format:

```
# ignore comments
t:0
[i0
 v120
 v150~10
 n5
 p5~4;3
 r1
]
#
```

* `t` is track
* `i` is instrument
* `p` is "play" for `On` steps, with optional arguments `~Off` steps, `>Push` blips, and `;Reduce` blips
  * `Push` means to start playing late by that many blips
    * i.e, the note starts at `+Push blips`, with rest occurring before this.
    * if `Off` is zero, then it will automatically cut off the note as well after `On` steps from the
      play's start position (not from when it turned on), i.e. `Reduce` will be at least `Push`.
    * if `Off` is nonzero, then `p` will play for the full length of `On` steps, but reduce the
      trailing amount of rest after playing by `Off - Push blips`.
  * `Reduce`, if non-zero, means to play the note as stacatto, by reducing the note's length by that many blips.
    * has some interaction with `Push`, but the main idea is to keep the duration of this event to
      `On` + `Off` steps.
* `r` is rest with an arg for how long.
* `v` is volume with args `Desired` and optional `~After_steps` argument
* `n` is note pitch, relative to current global pitch offset, with args `Desired` and optional `~After_steps`.
