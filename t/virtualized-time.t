use Test;
use Test::Scheduler;

{
    my $*SCHEDULER = Test::Scheduler.new;
    my $p = Promise.in(0.001);
    nok $p, 'Promise in 0.001 seconds not kept yet';
    sleep 0.1;
    nok $p, 'Promise in 0.001 seconds not kept even after 0.1 seconds of real time';

    $*SCHEDULER.advance-by(0.001);
    await $p;
    ok $p, 'Promise kept upon advancing scheduler';
}

{
    my $*SCHEDULER = Test::Scheduler.new;
    my $p = Promise.in(200);
    nok $p, 'Promise in 200 seconds not kept yet';
    for 20, 40 ... 180 {
        $*SCHEDULER.advance-by(20);
        nok $p, "Promise still next kept after advancing scheudler by $_ seconds";
    }
    my $before = now;
    $*SCHEDULER.advance-by(20);
    await $p;
    ok $p, 'Promise kept upon advancing scheduler to 200 seconds';
    ok now - $before < 2, 'Certainly did not take 200 seconds; time is virtual';
}

{
    my $*SCHEDULER = Test::Scheduler.new;
    my $p1 = Promise.in(20);
    my $p2 = Promise.in(40);

    $*SCHEDULER.advance-by(20);
    await $p1;
    ok $p1, 'Promise 1 in 20s kept upon advancing to 20s';
    my $p3 = Promise.in(10);
    nok $p2, 'Promise at 40s not yet kept';
    nok $p3, 'New promise at 10s (relative to current 20s) not yet kept';

    $*SCHEDULER.advance-by(10);
    await $p3;
    ok $p3, 'Promise 3 kept after a further 10s';
    nok $p2, 'Promise at 40s from start point not yet kept';

    $*SCHEDULER.advance-by(10);
    await $p3;
    ok $p3, 'Promise at 40s kept after a further 10s';

    throws-like { $*SCHEDULER.advance-by(-1) }, X::Test::Scheduler::BackInTime;

    my $p4 = Promise.in(0);
    await $p4;
    ok $p4, 'Promise in 0 seconds is scheduled immediately; no need to advance';
}

{
    my $sim-time = now + 50000;
    my $*SCHEDULER = Test::Scheduler.new(virtual-time => $sim-time);
    is $*SCHEDULER.virtual-time, $sim-time, 'Can set virtual time in constructor';
    $*SCHEDULER.advance-by(10);
    is $*SCHEDULER.virtual-time, $sim-time + 10, 'Virtual time advances';

    my $p1 = Promise.new;
    my $p2 = Promise.new;
    $*SCHEDULER.cue: { $p1.keep(42) }, :at($sim-time + 40);
    $*SCHEDULER.cue: { $p2.keep(101) }, :at($sim-time + 30);
    $*SCHEDULER.advance-by(20);
    is await($p2), 101, 'Scheduling with at works in virtual time (kept at sim + 30s)';
    nok $p1, 'Still not kept promise at sim + 40s yet';

    $*SCHEDULER.advance-by(10);
    is await($p1), 42, 'After another 10s, kept promise at sim + 40s';

    my $p3 = Promise.new;
    $*SCHEDULER.cue: { $p3.keep(22) }, :at($sim-time + 40);
    is await($p3), 22, 'Promise at current virtual time scheduled immediately';
}

done-testing;
