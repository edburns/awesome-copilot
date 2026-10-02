use strict;
use warnings;
use Time::HiRes qw(clock_gettime CLOCK_MONOTONIC);
use POSIX qw(:sys_wait_h);

# Bash has no portable monotonic clock or subprocess timeout on GNU/Linux/macOS.
my $mode = shift @ARGV // '';
if ($mode eq 'now') {
    printf "%.0f\n", clock_gettime(CLOCK_MONOTONIC) * 1000;
    exit 0;
}
die "Usage: $0 now | run TIMEOUT_MS COMMAND [ARG ...]\n"
    unless $mode eq 'run' && @ARGV >= 2;
my $timeout = shift @ARGV;
die "TIMEOUT_MS must be positive\n" unless $timeout =~ /^\d+$/ && $timeout > 0;
my $pid = fork();
die "fork: $!\n" unless defined $pid;
if ($pid == 0) {
    exec { $ARGV[0] } @ARGV;
    die "exec: $!\n";
}
my $deadline = clock_gettime(CLOCK_MONOTONIC) + $timeout / 1000;
while (1) {
    my $result = waitpid($pid, WNOHANG);
    if ($result == $pid) {
        exit(($? & 127) ? 128 + ($? & 127) : $? >> 8);
    }
    die "waitpid: $!\n" if $result == -1;
    if (clock_gettime(CLOCK_MONOTONIC) >= $deadline) {
        kill 'KILL', $pid;
        waitpid($pid, 0);
        print STDERR "GitHub command exceeded its remaining request budget\n";
        exit 124;
    }
    Time::HiRes::sleep(0.02);
}
