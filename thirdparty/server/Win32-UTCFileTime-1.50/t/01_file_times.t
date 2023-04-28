#!perl
#===============================================================================
#
# t/01_file_times.t
#
# DESCRIPTION
#   Test script to check getting/setting file times.
#
# COPYRIGHT
#   Copyright (C) 2003-2006 Steve Hay.  All rights reserved.
#
# LICENCE
#   You may distribute under the terms of either the GNU General Public License
#   or the Artistic License, as specified in the LICENCE file.
#
#===============================================================================

use 5.006000;

use strict;
use warnings;

use Test::More tests => 67;

#===============================================================================
# INITIALIZATION
#===============================================================================

BEGIN {
    use_ok('Win32::UTCFileTime');
}

#===============================================================================
# MAIN PROGRAM
#===============================================================================

MAIN: {
    my $file = 'test.txt';

    my($fh, $time, $errno, $lasterror, @stats, @lstats, @alt_stats);

    unlink $file or die "Can't delete file '$file': $!\n" if -e $file;
    open $fh, ">$file" or die "Can't create file '$file': $!\n";
    close $fh;
    $time  = time;
    @stats = stat $file;
    ($errno, $lasterror) = ($!, $^E);
    ok(scalar @stats, 'stat() returns OK') or
        diag("\$! = '$errno', \$^E = '$lasterror'");
    # Do not check $stats[8] (last access time): not stored on FAT.
    # Allow for 2 second granularity on FAT.
    cmp_ok(abs($time - $stats[9]), '<', 3,
           '... and gets mtime correctly: ' . scalar gmtime $stats[9]);
    # Do not check $stats[10] (creation time): often gets cached value.

    unlink $file or die "Can't delete file '$file': $!\n" if -e $file;
    open $fh, ">$file" or die "Can't create file '$file': $!\n";
    close $fh;
    $time   = time;
    @lstats = lstat $file;
    ($errno, $lasterror) = ($!, $^E);
    ok(scalar @lstats, 'lstat() returns OK') or
        diag("\$! = '$errno', \$^E = '$lasterror'");
    # Do not check $lstats[8] (last access time): not stored on FAT.
    # Allow for 2 second granularity on FAT.
    cmp_ok(abs($time - $lstats[9]), '<', 3,
           '... and gets mtime correctly: ' . scalar gmtime $lstats[9]);
    # Do not check $lstats[10] (creation time): often gets cached value.

    unlink $file or die "Can't delete file '$file': $!\n" if -e $file;
    open $fh, ">$file" or die "Can't create file '$file': $!\n";
    close $fh;
    $time   = time;
    @alt_stats = Win32::UTCFileTime::alt_stat($file);
    ($errno, $lasterror) = ($!, $^E);
    ok(scalar @alt_stats, 'alt_stat() returns OK') or
        diag("\$! = '$errno', \$^E = '$lasterror'");
    # Do not check $alt_stats[8] (last access time): not stored on FAT.
    # Allow for 2 second granularity on FAT.
    cmp_ok(abs($time - $alt_stats[9]), '<', 3,
           '... and gets mtime correctly: ' . scalar gmtime $alt_stats[9]);
    # Do not check $alt_stats[10] (creation time): often gets cached value.

    unlink $file or die "Can't delete file '$file': $!\n" if -e $file;
    open $fh, ">$file" or die "Can't create file '$file': $!\n";
    close $fh;
    $time = time;
    for my $i (-7 .. 7) {
        my $age = $i * 5000000;
        my $utime = $time + $age;

        my $ret = utime $utime, $utime, $file;
        ($errno, $lasterror) = ($!, $^E);
        ok($ret, 'utime() returns OK for time ' . scalar gmtime $utime) or
            diag("\$! = '$errno', \$^E = '$lasterror'");

        @stats = stat $file;
        # Do not check $stats[8] (last access time): not stored on FAT.
        # Allow for 2 second granularity on FAT.
        cmp_ok(abs($utime - $stats[9]), '<', 3,
               '... and sets mtime correctly according to stat()');
        # Do not check $stats[10] (creation time): not set by utime().

        @lstats = lstat $file;
        # Do not check $lstats[8] (last access time): not stored on FAT.
        # Allow for 2 second granularity on FAT.
        cmp_ok(abs($utime - $lstats[9]), '<', 3,
               '... and sets mtime correctly according to lstat()');
        # Do not check $lstats[10] (creation time): not set by utime().

        @alt_stats = Win32::UTCFileTime::alt_stat($file);
        # Do not check $alt_stats[8] (last access time): not stored on FAT.
        # Allow for 2 second granularity on FAT.
        cmp_ok(abs($utime - $alt_stats[9]), '<', 3,
               '... and sets mtime correctly according to alt_stat()');
        # Do not check $alt_stats[10] (creation time): not set by utime().
    }

    unlink $file;
}

#===============================================================================
