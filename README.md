# Doors.jl 🚪

|  **Build Status**                 |
|:---------------------------------:|
|  [![][actions-img]][actions-url]  |

another implement of [DaemonMode.jl](https://github.com/dmolina/DaemonMode.jl).
I used some code from DaemonMode.jl.

```
alias jd="julia -i -e 'using Doors; serve()'  "
alias jc="julia    -e 'using Doors; runargs()'  "
```

### Advanced usage
```
alias jd="julia -i --trace-compile-timing --trace-compile=stderr --compiled-modules=yes -e 'using Doors; serve(; into=Main)'  "
alias jc="julia    --trace-compile-timing --trace-compile=stderr --compiled-modules=yes -e 'using Doors; runargs()'  "
```

### Listen to music - The Doors  - The Crystal Ship (MIDI)
[![The Doors  - The Crystal Ship (MIDI)](http://img.youtube.com/vi/NlB4DARURM0/1.jpg)](http://www.youtube.com/watch?v=NlB4DARURM0)

[actions-img]: https://github.com/wookay/Doors.jl/workflows/CI/badge.svg
[actions-url]: https://github.com/wookay/Doors.jl/actions
