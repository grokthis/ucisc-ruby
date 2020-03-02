# MicroCisc

Sketch Emulator/VM implementation for https://github.com/grokthis/ucisc

## Installation

Prerequisites: Bundler 2

```
$ git clone https://github.com/grokthis/ucisc-ruby
$ cd ucisc-ruby
$ bundle install
```

Eventually, once the gem stabilizes a bit, I will host it on
rubygems. I don't want to do that until the code stabilizes a
bit and a release cadence doesn't get in the way. In the mean
time, you can install the gem locally by doing:

```
bundle exec rake install
```

This will let you simply run `ucisc` as a command assuming your
path is setup to load gem binaries.

This gem is only ever intended to be a prototype compiler and
VM. It's useful to get uCISC code running anywhere ruby can run
but ultimately the goal is to get it self bootstrapping. It will
always need a VM of sorts as the instruction set is fundamentally
different from x86, ARM or others, but I intend to write a better
performing VM in SubX or Mu. That said, this project will likely
be around a while.

## Usage

The `ucisc` command combines the compilation and VM execution.

```
# Run the factorial example
$ exe/ucisc examples/factorial.ucisc
```

You will get 3 outputs:
1. Line numbered output with instructions encoded (label values are all 0)
2. Final instruction output with address numbers and final label substitutions
3. Instruction by instruction execution details, including the result "value"

Example line numbers:

```
18: Entry
20: 0x763F  0/load 0xFFFF to sp/    4.val -1.imm 5.reg
22: 0x6443  0 0.reg 6.imm 1.mem 1.inc 3.eff #   (1.mem fib 4.val 8.imm)
22: 0x6648  0 4.val 8.imm 1.mem 1.inc 3.eff #   (1.mem fib 4.val 8.imm)
22: 0x6000  0 0.reg fib.disp 0.reg 0.inc 3.eff #   (1.mem fib 4.val 8.imm)
...
```
i
Note: as you can see in the example above, the function call
gets added to each generated push and call command it generates.

This is the preliminary compile step and you can see the line
number, compiled instruction in hex and the original line.
Comment lines and blank lines are ignored. Any labels evaluate
to 0x0000 at this stage. See line 22 above for example.

After line numbers, the second pass produces the binary output
after subtituting the label offset calculations. You get
something like this:

```
0: 0x763F  0/load 0xFFFF to sp/    4.val -1.imm 5.reg
2: 0x6443  0 0.reg 6.imm 1.mem 1.inc 3.eff #   (1.mem fib 4.val 8.imm)
4: 0x6648  0 4.val 8.imm 1.mem 1.inc 3.eff #   (1.mem fib 4.val 8.imm)
6: 0x6002  0 0.reg fib.disp 0.reg 0.inc 3.eff #   (1.mem fib 4.val 8.imm)
```

The line numbers are now the hex memory address of the
instruction followed by the final hex instruction code and the
original statement that produced it.

The vm will then execute the code. Any instruction that sets
the PC address to 0x0000 will cause the VM to break execution
and give you a prompt.

```
Running program with 60 bytes
Jump 0x000 detected...
Finished 929 instructions in 0.010282s
> _
```

You can see the compiled program is 60 bytes total including any
data and instructions encoded. In this case, 929 instructions
were executed.

At the prompt, you can do the following:

* Type "exit" - exits the VM
* Type "break" - opens the ruby debugger. You can inspect the
  memory and registers from here if desired.
* Simply hit <enter> and the execution will continue

When in the ruby debugger, you can do the following to look at
the stack value:

```
# Dereference register 1 and unpack the value
instruction.unpack(load(register(1)))
```

## Debugging

You can debug your code by doing the following:

```
# Debug the factorial example
$ exe/ucisc examples/factorial.ucisc -d
```

Instead of simply executing all the code, the debugger will
pause after each instruction:

```
Running program with 60 bytes
0000 0x0 R: 4, D: 5, E: 3, M: false, I: -1, value: -1, store > 
0002 0x0 R: 0, D: 1, E: 3, M: true, I: 6, value: 8, store > 
0004 0x0 R: 4, D: 1, E: 3, M: true, I: 8, value: 8, store > 
0006 0x0 R: 0, D: 0, E: 3, M: false, I: 4, value: 10, store > 
000a 0x202 R: 1, D: 1, Sign: 1, Inc: false, Eff: 3, value: 8, skipping store > 
000c 0x0 R: 0, D: 0, E: 1, M: false, I: 4, value: 16, store > 
```

Notice the prompt after each instruction. The same break, exit
or <enter> options are available as described above. The output
lists the component parts of the instruction as decoded. The
value is the value that was moved, manipulated or calculated.
The final "store" or "skipping store" indicates if the value
was actually saved to the destination or not (depending on the
effect modifier).

Note the 4-digit hex address to the left. That is the address
of the instruction that was executed and will match the compiled
output (assuming your code doesn't overwrite itself).

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/grokthis/micro_cisc. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/grokthis/micro_cisc/blob/master/CODE_OF_CONDUCT.md).


## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the MicroCisc project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/grokthis/micro_cisc/blob/master/CODE_OF_CONDUCT.md).
