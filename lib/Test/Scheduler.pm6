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
        has Bool $.cancelled = False;
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
            !!! ":every NYI in test scheduler";
        }

        # only after waiting a bit or more than once
        elsif $delay or $times > 1 {
            my &schedulee := &catch
                ?? -> { code(); CATCH { default { catch($_) } } }
                !! &code;
            my @to-cancel;
            for 1 .. $times {
                my $virtual-time = $!virtual-time + $delay;
                given FutureEvent.new(:&schedulee, :$virtual-time) {
                    push @!future, $_;
                    push @to-cancel, $_;
                }
            }
            self!run-due();
            # XXX Cancellation
            return Nil;
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
        my (:@now, :@future) := @!future.classify: {
            .virtual-time <= $!virtual-time ?? 'now' !! 'future'
        }
        @!future := @future;
        for @now {
            $!wrapped-scheduler.cue(.schedulee);
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
