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
#use warnings;
#use diagnostic;
use Carp qw(cluck croak);
use Data::Dumper;
use Sys::Syslog;
use Config::General;
my $cfgfile="/etc/lvautoresize.conf";
my $dry_run = 0; # dont actually do anything
my $verbose = 0; # be verbose. turn off if u wanna use it from cron

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
	# TODO add optional "resize max(min_free,step_size)"
	my $step_size = &get_bytes($lvconfig->{'step_size'});
	if(defined($fs)) {
	    # sanity check
	    if($fs->{'total'} <= 0) {
		croak "Somehow total filesystem capacity returned by df is 0 or below, failing\n";
	    }
	    if($fs->{'free'} < $min_free) {
		&info("Volume $lv_path smaller than min_free, resizing\n");
		&resize($lv_path, $fs->{'type'}, $step_size);
	    }
	    elsif ( ( $fs->{'free'} / $fs->{'total'} ) < $min_free_percent ) {
		&info("Volume $lv_path % of free space smalller than min_free_percent, resizing\n");
		&resize($lv_path, $fs->{'type'}, $step_size);
	    } else {
		# resize not needed
	    }
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
    my $fs_type = shift;
    my $step_size = shift;
    if (defined($config->{'filesystem'}{$fs_type}{'resize_cmd'} . "\n")) {
	my $resize_cmd = $config->{'filesystem'}{$fs_type}{'resize_cmd'};
	# TODO check if lv_size > partition_size (plus some MBs) then don't do resize
	# so when previous run only resized LV but not partition on it (because of error)
	# we won't resize it at infinitum
	my $lvresize_txt = `/sbin/lvresize -L +$step_size $lv_path 2>&1`;
	my $lvresize_exit_code = int( $? / 256 );
	if($lvresize_exit_code == 0) {
	    info($lvresize_txt);
	    my $fsresize_txt = `$resize_cmd $lv_path 2>&1`;
	    my $fsresize_exit_code = int( $? / 256 );
	    if ($fsresize_exit_code == 0) {
		info($fsresize_txt);
		info("Resizing of $lv_path suceeded\n");
	    }
	    else {
		error($fsresize_txt);
		error("Resize of filesystem on $lv_path failed!\n");
		return 1
	    }
	}
	else {
	    error($lvresize_txt);
	    error("Resize of LV $lv_path failed!\n");
	    return 1
	}
    }
    else {
	error("resize_cmd for fs $fs_type not defined!\n");
	return 1
    }
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
