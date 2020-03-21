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
$ exe/ucisc examples/fib.ucisc
```

You will get 3 outputs:
1. Line numbered output with instructions encoded (label values are all 0)
2. Final instruction output with address numbers and final label substitutions
3. Instruction by instruction execution details, including the result "value"

This code:

```
...
13: Entry:
14:   # Initialize the stack register to 0x0000, decrement on push will change to 0xFFFF
15:   0/load 0xFFFF to sp/               4.val 0.imm 1.reg
16:
17:   (1.mem fib 4.val 8.imm)
...
```
Gets translated into these instructions:

```
13: Entry
15: 0x7600  0/load 0xFFFF to sp/               4.val 0.imm 1.reg
17: 0x6443  0 0.reg 3.imm 1.mem 1.push #   (1.mem fib 4.val 8.imm)
17: 0x6648  0 4.val 8.imm 1.mem 1.push #   (1.mem fib 4.val 8.imm)
17: 0x6000  0 0.reg fib.disp 0.reg #   (1.mem fib 4.val 8.imm)
...
```

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
...
```

The line numbers are now the hex memory address of the
instruction followed by the final hex instruction code and the
original statement that produced it.

The vm will then execute the code. Any instruction that sets
the PC address to 0x0000 will cause the VM to break execution
and give you a prompt.

```
Running program with 60 bytes
Starting program... (enter to continue)
0000 0x0 4.val 0x0 1.reg 3.eff 0.push # value: 0, stored > _
```
You can see the compiled program is 60 bytes total including any
data and instructions encoded. The program is loaded and ready to
execute at this point. The last line shows the instruction that is
about to be executed. Press [enter] to continue and run the
program to completion.

```
Breaking on jump to 0x0000...
Finished 929 instructions in 0.001835s
0000 0x0 4.val 0x0 1.reg 3.eff 0.push # value: 0, stored > _
```
When the program jumps to address 0x0000, the program pauses. In
this case, 929 instructions were executed in 0.001835s. Performance
will depend on your ruby version, computer performance and program.
I've seen up to 6x the performance of the 8-bit computers of the
early 80's when running on modern CPU's, so that gives you an idea
of what types of algorithms you can run.

At the prompt, you can do the following:

* Type "exit" - exits the VM
* Type "break" - opens the ruby debugger. You can inspect the
  memory and registers from here if desired.
* "next", "n" - Turn debug mode on and step to the next instruction.
* "continue", "c" - Turn debug mode off and continue execution
* Simply hit "enter" and the execution will continue. If in debug
  mode, it will execute the instruction and move to the next. If
  not debugging it will continue running until the next jump 0x0000.

When in the ruby debugger, you can do the following to look at
the stack value:

```
# Load a value from memory; returns 16-bit word
# Returns nil if the address is out of memory bounds
load(address)

# Look at the contents of a register; number is 1-3
# Returns 16-bit register value
register(number)

# PC contents
pc

# Flags register
flags

# Values are show in decimal, conver to hex with:
pc.to_s(16).upcase

# To continue execution (any byebug commands are available)
# https://github.com/deivid-rodriguez/byebug
continue

# Combine as needed
# Look at the stack: load the address in r1
load(register(1)).to_s(16).upcase
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
0000 0x0 4.val 0x0 1.reg 3.eff 0.push # value: 0, stored >
0001 0x0 0.reg 0x3 1.mem 3.eff 1.push # value: 4, stored >
0002 0x0 4.val 0x8 1.mem 3.eff 1.push # value: 8, stored >
0003 0x0 0.reg 0x2 0.reg 3.eff 0.push # value: 5, stored >
0005 0x202 1.mem 1.mem 0.inc 1.sign 3.eff # arg1: 8, arg2: 8, result 8, not stored >
0006 0x0 0.reg 0x2 0.reg 1.eff 0.push # value: 8, stored >
0008 0x0 4.val 0x1 2.reg 3.eff 0.push # value: 1, stored >
0009 0x20c 2.reg 1.mem 0.inc 1.sign 3.eff # arg1: 1, arg2: 8, result 7, not stored >
000a 0x0 0.reg 0x2 0.reg 1.eff 0.push # value: 12, stored >
000c 0x0 1.mem 0x0 1.mem 3.eff 1.push # value: 8, stored > _
```

Notice the prompt after each instruction. The same break, exit
or "enter" options are available as described above. The output
at each line is the uCISC equivalent of what was executed.
After the comment, the value result and whether or not the value
was stored is indicated. ALU instructions also include both args
in the comment.

Note the 4-digit hex address to the left. That is the address
of the instruction that was executed and will match the compiled
output (assuming your code doesn't overwrite itself or load code
to other memory locations).

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/grokthis/micro_cisc. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/grokthis/micro_cisc/blob/master/CODE_OF_CONDUCT.md).


## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the MicroCisc project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/grokthis/micro_cisc/blob/master/CODE_OF_CONDUCT.md).
