#!/usr/bin/perl

#    lvautoresize - automatically resizes LVs
#    Copyright (C) 2008-2011  Mariusz Gronczewski

#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.

#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
use strict;
use warnings;
use Carp qw(cluck);
use Data::Dumper;
use Sys::Syslog;
use Config::General;
my $cfgfile="/etc/lvauto.conf";
my $dry_run = 1; # dont actually do anything
my $verbose = 1; # be verbose. turn off if u wanna use it from cron

# TODO add syslog logging to log functions
# openlog('lvautoresize', 'cons,perror,nofatal', 'LOG_USER') or die "Can't open syslog";

my $config_tmp = new Config::General(-ConfigFile => $cfgfile,
                         -MergeDuplicateBlocks => 'true',
                         -MergeDuplicateOptions => 'true',
				 -AllowMultiOptions => 'true');
my %config = $config_tmp->getall();
my $config = \%config;
my $vglist=$config->{'vg'};
while( my($vgname, $vg) = each (%$vglist)) {
    my $lvs=$vg->{'lv'};
    while( my($lvname, $lvconfig) = each (%$lvs)) {
	my $lv_path = &get_lv_path($vgname, $lvname);
	my $fs = &get_fs_info($lv_path);
	my $min_free = &get_bytes($lvconfig->{'min_free'});
	my $min_free_percent = $lvconfig->{'min_free_percent'} / 100;
	my $step_size = &get_bytes($lvconfig->{'step_size'});
	if(defined($fs)) {
	    # sanity check
	    if($fs->{'total'} <= 0) {croak "Somehow total filesystem capacity returned by df is 0 or below, failing\n"}
	    if($fs->{'free'} < $min_free) {
		&info("Volume $lv_path smaller than min_free, resizing\n");
		&resize($lv_path, $fs->{'type'}, $step_size);
	    }
	    elsif ( ( $fs->{'free'} / $fs->{'total'} ) < $min_free_percent ) {
		&info("Volume % of free space smalller than min_free_percent, resizing\n"
		&resize($lv_path, $fs->{'type'}, $step_size);
	}
	else {
	    &warning("Filesystem on VG $vgname LV $lvname is not mounted, ignoring\n");
	}
    }
}


sub dump_config() {
    my $config = shift;
    my $vglist=$config->{'vg'};
    while( my($vgname, $volume) = each (%$vglist)) {
	my $lv=$volume->{'lv'};
	&info("VG: $vgname\n");
	while( my($lvname, $lvconfig) = each (%$lv)) {
	    &info(" LV: $lvname\n");
	    &info("  min_size: $lvconfig->{'min_free'}\n") ;
	    &info("  min_free_percent: $lvconfig->{'min_free'}\n") ;
	    &info("  step_size: $lvconfig->{'min_free'}\n") ;
	}
    }
}

sub resize() {
    my $lv_path = shift;
    my $fs_type;
    my $step_size;
    print "Dummy resize of $lv_path by $step_size with fs $fs_type\n";
    return;
}

sub get_bytes() {
    my $value = shift;
    if ($value =~ /[Gg]/) {
	$value *= 1024 * 1024 * 1024;
    }
    elsif ($value =~ /[Mm]/) {
	$value *= 1024 * 1024;
    }
    elsif ($value =~ /[Kk]/) {
	$value *= 1024;
    }
    return $value;
}

sub get_lv_path() {
    my $vg = shift;
    my $lv = shift;

    # udev changes "-" to "--" in lv/vg name when doing dev nodes
    $lv =~ s/-/--/g;
    $vg =~ s/-/--/g;

    return "/dev/mapper/$vg-$lv";
}

sub get_fs_info() {
    my $lv_path = shift;
    open(DF, "df -k -P -T $lv_path  2>/dev/null |");
    $_=<DF>; # skip header
    $_=<DF>;
    if (!defined) { #empty df, means filesystem isn't mounted
	return undef
    }
    my @tmp=split;
    my %fs;
    $fs{'type'}=$tmp[1];
    $fs{'total'}=$tmp[2]*1024;
    $fs{'used'}=$tmp[3]*1024;
    $fs{'free'}=$tmp[4]*1024;
    return \%fs;
}
sub info() {
    if (defined($verbose) && $verbose > 0) {
	print shift;
    }
}

sub warning() {
    print shift
}

sub error {
    print shift
}
