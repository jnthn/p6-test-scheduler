my $original-scheduler = INIT $*SCHEDULER;

class X::Test::Scheduler::BackInTime is Exception {
    method message() {
        "Test scheduler can not go backwards in time";
    }
}

class Test::Scheduler does Scheduler {
    my class FutureEvent {
        has &.schedulee is required;
        has $.virtual-time is required;
        has $.reschedule-after;
        has $.cancellation;
    }

    has $!wrapped-scheduler;
    has $.virtual-time = now;
    has @!future;

    submethod BUILD(
        :wrap($!wrapped-scheduler) = $original-scheduler,
        :$!virtual-time = now
    ) { }

    method cue(&code, :$at, :$in, :$every, :$times = 1, :&stop is copy, :&catch ) {
        die "Cannot specify :at and :in at the same time"
          if $at.defined and $in.defined;
        die "Cannot specify :every, :times and :stop at the same time"
          if $every.defined and $times > 1 and &stop;
        my $delay = $at ?? $at - $!virtual-time !! $in // 0;

        # need repeating
        if $every {
            # generate a stopper if needed
            if $times > 1 {
                my $todo = $times;
                my $lock = Lock.new;
                &stop = { $lock.protect: { $todo ?? !$todo-- !! True } }
            }

            # we have a stopper
            if &stop {
                my $cancellation = Cancellation.new;
                push @!future, FutureEvent.new(
                    schedulee => &catch
                        ?? -> {
                            stop()
                                ?? $cancellation.cancel
                                !! code();
                            CATCH { default { catch($_) } };
                        }
                        !! -> {
                            stop()
                                ?? $cancellation.cancel
                                !! code();
                        },
                    virtual-time => $!virtual-time + $delay,
                    reschedule-after => $every,
                    cancellation => $cancellation
                );
                self!run-due();
                return $cancellation;
            }
            # no stopper
            else {
                my $cancellation = Cancellation.new;
                push @!future, FutureEvent.new(
                    schedulee => &catch
                        ?? -> { code(); CATCH { default { catch($_) } } }
                        !! &code,
                    virtual-time => $!virtual-time + $delay,
                    reschedule-after => $every,
                    cancellation => $cancellation
                );
                self!run-due();
                return $cancellation;
            }
        }

        # only after waiting a bit or more than once
        elsif $delay or $times > 1 {
            my &schedulee := &catch
                ?? -> { code(); CATCH { default { catch($_) } } }
                !! &code;
            my $cancellation = Cancellation.new;
            my $virtual-time = $!virtual-time + $delay;
            for 1..$times {
                @!future.push: FutureEvent.new(:&schedulee, :$virtual-time, :$cancellation);
            }
            self!run-due();
            return $cancellation;
        }

        # just cue the code
        else {
            $!wrapped-scheduler.cue(&code, :&catch);
            return Nil;
        }
    }

    method advance-by($seconds --> Nil) {
        die X::Test::Scheduler::BackInTime.new if $seconds < 0;
        $!virtual-time += $seconds;
        self!run-due();
    }

    method advance-to(Instant $new-virtual-time --> Nil) {
        die X::Test::Scheduler::BackInTime.new if $new-virtual-time < $!virtual-time;
        $!virtual-time = $new-virtual-time;
        self!run-due();
    }

    method !run-due() {
        loop {
            my (:@now, :@future) := @!future.classify: {
                .virtual-time <= $!virtual-time ?? 'now' !! 'future'
            }
            @!future := @future;
            return unless @now;
            for @now {
                next if .cancellation.?cancelled;
                $!wrapped-scheduler.cue(.schedulee);
                if .reschedule-after {
                    @!future.push(.clone(
                        virtual-time => .virtual-time + .reschedule-after
                    ));
                }
            }
        }
    }

    method uncaught_handler(|c) is raw {
        $!wrapped-scheduler.uncaught_handler(|c)
    }

    method handle_uncaught(|c) is raw {
        $!wrapped-scheduler.handle_uncaught(|c)
    }

    method loads(|c) is raw {
        $!wrapped-scheduler.loads(|c)
    }
}
