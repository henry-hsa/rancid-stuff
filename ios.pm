package ios;
##
## rancid 3.13
## Copyright (c) 1997-2019 by Henry Kilmer and John Heasley
## All rights reserved.
##
## This code is derived from software contributed to and maintained by
## Henry Kilmer, John Heasley, Andrew Partan,
## Pete Whiting, Austin Schutz, and Andrew Fort.
##
## Redistribution and use in source and binary forms, with or without
## modification, are permitted provided that the following conditions
## are met:
## 1. Redistributions of source code must retain the above copyright
##    notice, this list of conditions and the following disclaimer.
## 2. Redistributions in binary form must reproduce the above copyright
##    notice, this list of conditions and the following disclaimer in the
##    documentation and/or other materials provided with the distribution.
## 3. Neither the name of RANCID nor the names of its
##    contributors may be used to endorse or promote products derived from
##    this software without specific prior written permission.
##
## THIS SOFTWARE IS PROVIDED BY Henry Kilmer, John Heasley AND CONTRIBUTORS
## ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
## TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
## PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COMPANY OR CONTRIBUTORS
## BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
## CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
## SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
## INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
## CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
## ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
## POSSIBILITY OF SUCH DAMAGE.
##
## It is the request of the authors, but not a condition of license, that
## parties packaging or redistributing RANCID NOT distribute altered versions
## of the etc/rancid.types.base file nor alter how this file is processed nor
## when in relation to etc/rancid.types.conf.  The goal of this is to help
## suppress our support costs.  If it becomes a problem, this could become a
## condition of license.
# 
#  The expect login scripts were based on Erik Sherk's gwtn, by permission.
# 
#  The original looking glass software was written by Ed Kern, provided by
#  permission and modified beyond recognition.
#
#  RANCID - Really Awesome New Cisco confIg Differ
#
#  ios.pm - Cisco IOS rancid procedures

use 5.010;
use strict 'vars';
use warnings;
no warnings 'uninitialized';
require(Exporter);
our @ISA = qw(Exporter);

use rancid 3.13;

our $proc;
our $ios;
our $found_version;
our $found_env;
our $found_diag;
our $found_inventory;
our $config_register;			# configuration register value

our %hwbuf;				# defined in ShowContCbus
our %hwmemc;				# defined in ShowContCbus
our %hwmemd;				# defined in ShowContCbus
our %hwucode;				# defined in ShowContCbus
our $supbootdisk;			# skip sup-bootflash if sup-bootdisk
					# worked
our $type;				# device model, from ShowVersion
our %ucode;				# defined in ShowContCbus

our $ssp;				# SSP/SSE info, from ShowVersion
our $sspmem;				# SSP/SSE info, from ShowVersion

our $C0;				# output formatting control
our $E0;
our $H0;
our $I0;
our $DO_SHOW_VLAN;

our $vss_show_module;			 # Use "show module switch" on 6k VSS systems

@ISA = qw(Exporter rancid main);
#XXX @Exporter::EXPORT = qw($VERSION @commandtable %commands @commands);

# load-time initialization
sub import {
    0;
}

# post-open(collection file) initialization
sub init {
    $proc = "";
    $ios = "IOS";
    $found_version = 0;
    $found_env = 0;
    $found_diag = 0;
    $found_inventory = 0;
    $config_register = undef;		# configuration register value

    $supbootdisk = 0;			# skip sup-bootflash if sup-bootdisk
					# worked
    $type = undef;			# device model, from ShowVersion

    $ssp = 0;				# SSP/SSE info, from ShowVersion
    $sspmem = undef;			# SSP/SSE info, from ShowVersion

    $C0 = 0;				# output formatting control
    $E0 = 0;
    $H0 = 0;
    $I0 = 0;
    $DO_SHOW_VLAN = 0;

    $vss_show_module = 0;		# Use "show module switch" on 6k VSS systems
    # add content lines and separators
    ProcessHistory("","","","!RANCID-CONTENT-TYPE: $devtype\n!\n");
    ProcessHistory("COMMENTS","keysort","B0","!\n");
    ProcessHistory("COMMENTS","keysort","D0","!\n");
    ProcessHistory("COMMENTS","keysort","F0","!\n");
    ProcessHistory("COMMENTS","keysort","G0","!\n");

    0;
}

# main loop of input of device output
sub inloop {
    my($INPUT, $OUTPUT) = @_;
    my($cmd, $rval);

TOP: while(<$INPUT>) {
	tr/\015//d;
	if (/[>#]\s?exit$/) {
	    $clean_run = 1;
	    last;
	}
	if (/^Error:/) {
	    print STDOUT ("$host clogin error: $_");
	    print STDERR ("$host clogin error: $_") if ($debug);
	    $clean_run = 0;
	    last;
	}
	while (/[>#]\s*($cmds_regexp)\s*$/) {
	    $cmd = $1;
	    if (!defined($prompt)) {
		$prompt = ($_ =~ /^([^#>]+[#>])/)[0];
		$prompt =~ s/([][}{)(+\\])/\\$1/g;
		print STDERR ("PROMPT MATCH: $prompt\n") if ($debug);
	    }
	    print STDERR ("HIT COMMAND:$_") if ($debug);
	    if (! defined($commands{$cmd})) {
		print STDERR "$host: found unexpected command - \"$cmd\"\n";
		$clean_run = 0;
		last TOP;
	    }
	    if (! defined(&{$commands{$cmd}})) {
		printf(STDERR "$host: undefined function - \"%s\"\n",
		       $commands{$cmd});
		$clean_run = 0;
		last TOP;
	    }
	    $rval = &{$commands{$cmd}}($INPUT, $OUTPUT, $cmd);
	    delete($commands{$cmd});
	    if ($rval == -1) {
		$clean_run = 0;
		last TOP;
	    }
	}
    }
}

# This routine parses "show version"
sub ShowVersion {
    my($INPUT, $OUTPUT, $cmd) = @_;
    my($slave, $slaveslot);
    print STDERR "    In ShowVersion: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	if (/^$prompt/) { $found_version = 1; last};
	next if (/^(\s*|\s*$cmd\s*)$/);
	next if (/^\s+\^$/);
	next if (/^Load for five/);
	next if (/^Time source is/);
	return(1) if (/Line has invalid autocommand /);
	return(1) if (/(invalid (input|command) detected|type help or )/i);
	return(0) if ($found_version);		# Only do this routine once
	return(-1) if (/(?:%|command)? authorization failed/i);
	# the pager can not be disabled per-session on the PIX
	if (/^(<-+ More -+>)/) {
	    my($len) = length($1);
	    s/^$1\s{$len}//;
	}

	if (/^Slave in slot (\d+) is running/) {
	    $slave = " Slave:";
	    $slaveslot = ", slot $1";
	    next;
	}
	if (/cisco ios.*(IOS-)?XE/i) { $ios = "XE"; }
	if (/^Application and Content Networking .*Software/) { $type = "CE"; }
	# treat the ACE like the Content Engines for matching endofconfig
	if (/^Cisco Application Control Software/) { $type = "CE"; }
	if (/^Cisco Storage Area Networking Operating System/) { $type = "SAN";}
	if (/^Cisco Nexus Operating System/) { $type = "NXOS";}
	/^Application and Content Networking Software Release /i &&
	    ProcessHistory("COMMENTS","keysort","F1", "!Image: $_") && next;
	/^Cisco Secure PIX /i &&
	    ProcessHistory("COMMENTS","keysort","F1", "!Image: $_") && next;
	# ASA "time-based licenses" - eg: bot-net
	/^This (PIX|platform) has a time-based license that will expire in\s+(\d{2,})\s+day.*$/ &&
	    ProcessHistory("COMMENTS","keysort","D1",
			   "!This $1 has a time-based license\n") && next;
	# PIX 6 fail-over license, as in "This PIX has an Unrestricted (UR)
	# license."  PIX 7 as "his platform has ..."
	/^This (PIX|platform) has an?\s+(.*)$/ &&
	    ProcessHistory("COMMENTS","keysort","D1", "!$_") && next;
	/^(Cisco )?IOS .* Software,? \(([A-Za-z0-9_-]*)\), .*Version\s+(.*)$/ &&
	    ProcessHistory("COMMENTS","keysort","F1",
		"!Image:$slave Software: $2, $3\n") && next;
	/^([A-Za-z-0-9_]*) Synced to mainline version: (.*)$/ &&
	    ProcessHistory("COMMENTS","keysort","F2",
		"!Image:$slave $1 Synced to mainline version: $2\n") && next;
	/^Compiled (.*)$/ &&
	    ProcessHistory("COMMENTS","keysort","F3",
		"!Image:$slave Compiled: $1\n") && next;
	/^ROM: (IOS \S+ )?(System )?Bootstrap.*(Version.*)$/ &&
	    ProcessHistory("COMMENTS","keysort","G1",
		"!ROM Bootstrap: $3\n") && next;
	if (/^Hardware:\s+(.*), (.* RAM), CPU (.*)$/) {
	    ProcessHistory("COMMENTS","keysort","A1",
		"!Chassis type: $1 - a PIX\n");
	    ProcessHistory("COMMENTS","keysort","A2",
		"!CPU: $3\n");
	    ProcessHistory("COMMENTS","keysort","B1", "!Memory: $2\n");
	}
	/^serial number:\s+(.*)$/i &&
	    ProcessHistory("COMMENTS","keysort","C1", "!Serial Number: $1\n") &&
	    next;
	# More PIX stuff
	/^Encryption hardware device\s+:\s+(.*)/ &&
	    ProcessHistory("COMMENTS","keysort","A3", "!Encryption: $1\n") &&
	    next;
	/^running activation key\s*:\s+(.*)/i &&
	    ProcessHistory("COMMENTS","keysort","D2", "!Key: $1\n") &&
	    next;
	# Flash on the PIX or FWSM (FireWall Switch Module)
	/^Flash(\s+\S+)+ \@ 0x\S+,\s+(\S+)/ &&
	    ProcessHistory("COMMENTS","keysort","B2", "!Memory: Flash $2\n") &&
	    next;
	# 3750 switch stacks
	next if (/^Model revision number/ && $type eq "3750");
	next if (/^Motherboard/ && $type eq "3750");
	next if (/^Power supply/ && $type eq "3750");
	/^Model number                    : (.*)$/ && $type eq "3750" &&
	ProcessHistory("COMMENTS","keysort","C2", "!Model number:  $1\n") &&
 	    next;
	/^System serial number            : (.*)$/ && $type eq "3750" &&
	ProcessHistory("COMMENTS","keysort","C2", "!Serial number: $1\n") &&
 	    next;
	# CatOS 3500xl stuff
	/^system serial number\s*:\s+(.*)$/i &&
	    ProcessHistory("COMMENTS","keysort","C1", "!Serial Number: $1\n") &&
	    next;
	/^Model / &&
	    ProcessHistory("COMMENTS","keysort","C2", "!$_") && next;
	/^Motherboard / &&
	    ProcessHistory("COMMENTS","keysort","C3", "!$_") && next;
	/^Power supply / &&
	    ProcessHistory("COMMENTS","keysort","C4", "!$_") && next;

	/^Activation Key:\s+(.*)$/ &&
	    ProcessHistory("COMMENTS","keysort","C2", "!$_") && next;
	/^ROM: \d+ Bootstrap .*(Version.*)$/ &&
	    ProcessHistory("COMMENTS","keysort","G2",
		"!ROM Image: Bootstrap $1\n!\n") && next;
	/^ROM: .*(Version.*)$/ &&
	    ProcessHistory("COMMENTS","keysort","G3","!ROM Image: $1\n") && next;
	/^BOOTFLASH: .*(Version.*)$/ &&
	    ProcessHistory("COMMENTS","keysort","G4","!BOOTFLASH: $1\n") && next;
	/^BOOTLDR: .*(Version.*)$/ &&
	    ProcessHistory("COMMENTS","keysort","G4","!BOOTLDR: $1\n") && next;
	/^System image file is "([^\"]*)", booted via (\S*)/ &&
# removed the booted source due to
# CSCdk28131: cycling info in 'sh ver'
#	ProcessHistory("COMMENTS","keysort","F4","!Image: booted via $2, $1\n") &&
	    ProcessHistory("COMMENTS","keysort","F4","!Image: booted $1\n") &&
	    next;
	/^System image file is "([^\"]*)"$/ &&
	    ProcessHistory("COMMENTS","keysort","F5","!Image: $1\n") && next;
	# 2800 at least don't have a processor line
	if ((/(\S+(?:\sseries)?)\s+(?:\(([^)]+)\)\s+processor|\(revision[^)]+\)).*\s+with (\S+k) bytes/i) ||
	    (/isco\s+(\S+)\s+\(.+\)\s+with (\S+[kK]) bytes/)) {
	    $proc = $1;
	    my($cpu) = $2;
	    my($mem) = $3;

	    # the next line ought to be the more specific cpu info, grab it.
	    # yet, some boards/IOS vers have a processor ID line between these
	    # two.  grrr.  make sure we dont grab the "software" junk that
	    # follows these lines by looking for "CPU at " or the 2600s
	    # "processor: " unique string.  there are undoubtedly many other
	    # incantations.  for a slave, we dont get this info, its just a
	    # blank line.
	    $_ = <$INPUT>;
	    if (/processor board id/i) {
		my($sn);

		if (/processor board id (\S+)/i) {
		    $sn = $1;
		    $sn =~ s/,$//;
		    ProcessHistory("COMMENTS","keysort","D9",
				   "!Processor ID: $sn\n");
		}
		$_ = <$INPUT>;
	    }
	    # for 6500 sup-2t
	    if ($cpu =~ /M8572/) {
		if (defined($cpu)) {
		    s/^ CPU://;
		    ProcessHistory("COMMENTS","keysort","A3", "!CPU: $cpu, $_");
		}
LINE:		while (<$INPUT>) {
		    last LINE if /^\s*$/;
		    ProcessHistory("COMMENTS","keysort","A3", "!CPU: $_");
		    last LINE if /^\s*I-cache/;
		}
		undef ($cpu);
	    }
	    $_ = "" if (! /(cpu at |processor: |$cpu processor,)/i);
	    tr/\015//d;
	    s/implementation/impl/i;
	    if ($_ !~ /^\s*$/) {
		chomp;
		s/^/, /;
	    }

	    if ($proc eq "CSC") {
		$type = "AGS";
	    } elsif ($proc eq "CSC4") {
		$type = "AGS+";
	    } elsif ($proc =~ /1900/) {
		$type = "1900";
	    } elsif ($proc =~ /2811/) {
		$type = "2800";
            } elsif ($proc =~ /^ME-3400/) {
                $type = "ME3400";
            } elsif ($proc =~ /^ME-C37/) {
                $type = "ME3700";
            } elsif ($proc =~ /^ME-C65/) {
                $type = "ME6500";
	    } elsif ($proc =~ /C3750/) {
		$type = "3750";
	    } elsif ($proc =~ /^(AS)?25[12][12]/) {
		$type = "2500";
	    } elsif ($proc =~ /261[01]/ || $proc =~ /262[01]/) {
		$type = "2600";
	    } elsif ($proc =~ /WS-C29/) {
		$type = "2900XL";
	    } elsif ($proc =~ /WS-C355/) {
		$type = "3550";
	    } elsif ($proc =~ /WS-C35/) {
		$type = "3500XL";
	    } elsif ($proc =~ /^36[0246][0-9]/) {
		$type = "3600";
	    } elsif ($proc =~ /^37/) {
		$type = "3700";
            } elsif ($proc =~ /WS-C375/) {
                $type = "3750";
	    } elsif ($proc =~ /^38/) {
		$type = "3800";
	    } elsif ($proc =~ /WS-C45/) {
		$type = "4500";
	    } elsif ($proc =~ /^AS5300/) {
		$type = "AS5300";
	    } elsif ($proc =~ /^AS5350/) {
		$type = "AS5350";
	    } elsif ($proc =~ /^AS5400/) {
		$type = "AS5400";
	    } elsif ($proc =~ /^ASR920/) {
		$type = "ASR920";
	    } elsif ($proc =~ /6000/) {
		$type = "6000";
	    } elsif ($proc eq "WK-C65") {
		$type = "6500";
            } elsif ($proc =~ /WS-C6509/) {
                $type = "6500";
	    } elsif ($proc eq "RP") {
		$type = "7000";
	    } elsif ($proc eq "RP1") {
		$type = "7000";
	    } elsif ($proc =~ /720[246]/) {
		$type = "7200";
	    } elsif ($proc =~ /^73/) {
		$type = "7300";
	    } elsif ($proc eq "RSP7000") {
		$type = "7500";
	    } elsif ($proc =~ /RSP\d/) {
		$type = "7500";
	    } elsif ($proc =~ /OSR-76/) {
		$type = "7600";
	    } elsif ($proc =~ /CISCO76/) {
		$type = "7600";
	    } elsif ($proc =~ /1200[48]\/(GRP|PRP)/ || $proc =~ /1201[26]\/(GRP|PRP)/) {
		$type = "12000";
	    } elsif ($proc =~ /1201[26]-8R\/(GRP|PRP)/) {
		$type = "12000";
	    } elsif ($proc =~ /1240[48]\/(GRP|PRP)/ || $proc =~ /1241[06]\/(GRP|PRP)/) {
		$type = "12400";
	    } elsif ($proc =~ /AIR-L?AP1[12][1234][[1234]/) {
		$type="Aironet";
	    } else {
		$type = $proc;
	    }

	    print STDERR "TYPE = $type\n" if ($debug);
	    ProcessHistory("COMMENTS","keysort","A1",
		"!Chassis type:$slave $proc\n");
	    ProcessHistory("COMMENTS","keysort","B1",
		"!Memory:$slave main $mem\n");
	    if (defined($cpu)) {
		ProcessHistory("COMMENTS","keysort","A3",
			       "!CPU:$slave $cpu$_$slaveslot\n");
	    }
	    next;
	}
	if (/(\S+) Silicon\s*Switch Processor/) {
	    if (!$C0) {
		$C0 = 1; ProcessHistory("COMMENTS","keysort","C0","!\n");
	    }
	    ProcessHistory("COMMENTS","keysort","C2","!SSP: $1\n");
	    $ssp = 1;
	    $sspmem = $1;
	    next;
	}
	/^(\d+[kK]) bytes of multibus/ &&
	    ProcessHistory("COMMENTS","keysort","B2",
		"!Memory: multibus $1\n") && next;
	/^(\d+[kK]) bytes of (non-volatile|NVRAM)/ &&
	    ProcessHistory("COMMENTS","keysort","B3",
		"!Memory: nvram $1\n") && next;
	/^(\d+[kK]) bytes of (flash memory|processor board System flash|ATA CompactFlash)/ &&
	    ProcessHistory("COMMENTS","keysort","B5","!Memory: flash $1\n") &&
	    next;
	/^(\d+[kK]) bytes of .*flash partition/ &&
	    ProcessHistory("COMMENTS","keysort","B6",
		"!Memory: flash partition $1\n") && next;
	/^(\d+[kK]) bytes of Flash internal/ &&
	    ProcessHistory("COMMENTS","keysort","B4",
		"!Memory: bootflash $1\n") && next;
	if (/^(\d+[kK]) bytes of (Flash|ATA)?.*PCMCIA .*(slot|disk) ?(\d)/i) {
	    ProcessHistory("COMMENTS","keysort","B7",
		"!Memory: pcmcia $2 $3$4 $1\n");
	    next;
	}
	if (/^(\d+[kK]) bytes of (slot|disk)(\d)/i) {
	    ProcessHistory("COMMENTS","keysort","B7",
		"!Memory: pcmcia $2$3 $1\n");
	    next;
	}
	if (/^(\d+[kK]) bytes of physical memory/i) {
	    ProcessHistory("COMMENTS","keysort","B1", "!Memory: physical $1\n");
	    next;
	}
	if (/^WARNING/) {
	    if (!$I0) {
		$I0 = 1;
		ProcessHistory("COMMENTS","keysort","I0","!\n");
	    }
	    ProcessHistory("COMMENTS","keysort","I1","! $_");
	}
	if (/^Configuration register is (.*)$/) {
	    $config_register = $1;
	    next;
	}
	if (/^Configuration register on node \S+ is (.*)$/) {
	    $config_register = $1 if (length($config_register) < 1);
	    next;
	}
    }
    return(0);
}

# This routine parses "show activation-key" on ASA
sub ShowActivationKey {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowMTU: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	next if (/^\s+\^$/);
	next if (/^Load for five/);
	next if (/^Time source is/);
	return(1) if (/Line has invalid autocommand /);
	return(1) if (/(invalid (input|command) detected|type help or )/i);
	# the pager can not be disabled per-session on the PIX
	if (/^(<-+ More -+>)/) {
	    my($len) = length($1);
	    s/^$1\s{$len}//;
	}

	if (/^(failover|licensed) .* for this platform:/i ||
	    /^active .* activation key/i) {
	    ProcessHistory("COMMENTS","keysort","LICENSE","! $_");
	    # parse license features/permanents/etc until an empty line
	    while (<$INPUT>) {
		tr/\015//d;
		goto OUT if (/^$prompt/);	# should not occur
		s/\s*$//;			# trim trailing WS
		# the pager can not be disabled per-session on the PIX
		if (/^(<-+ More -+>)/) {
		    my($len) = length($1);
		    s/^$1\s{$len}//;
		}
		if (/^\s*$/) {
		    ProcessHistory("COMMENTS","keysort","LICENSE","!\n");
		    last;
		}
		if (/^([^:]+: \S+\s+)(.*)/) {
		    my($L) = $1;
		    my($T) = $2;
		    if ($T !~ /perpetual/i) {
			$T = "<limited>";
		    }
	    	    ProcessHistory("COMMENTS","keysort","LICENSE","! $L $T\n");
		} else {
		    ProcessHistory("COMMENTS","keysort","LICENSE","! $_\n");
		}
	    }
	    next;
	}
	ProcessHistory("COMMENTS","keysort","LICENSE","! $_");
    }
OUT:ProcessHistory("COMMENTS","keysort","LICENSE","!\n");
    return(0);
}

# This routine parses "show cellular 0 profile"
sub ShowCellular {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowCellular: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	next if (/^\s+\^$/);
	return(1) if (/Line has invalid autocommand /);
	return(1) if (/(invalid (input|command) detected|type help or )/i);

	# Ignore the PDP address and assigned DNS servers
	next if (/^pdp (ipv6 )?address/i);
	next if (/^\s*(primary|secondary) DNS (ipv6 )?address/i);

	ProcessHistory("COMMENTS","keysort","CELL","!CELL: $_");
    }
    ProcessHistory("COMMENTS","keysort","CELL","!\n");
    return(0);
}

# This routine parses "show switch detail"
sub ShowDetail {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowDetail: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	next if (/^\s+\^$/);
	next if (/^Load for five/);
	next if (/^Time source is/);

	next if (/^Load for five/);
	next if (/^Time source is/);
	return(1) if (/Line has invalid autocommand /);
	return(1) if (/(invalid (input|command) detected|type help or )/i);

	ProcessHistory("COMMENTS","keysort","IO","!STACK: $_");
    }
    ProcessHistory("COMMENTS","keysort","IO","!\n");
    return(0);
}

# This routine parses "show license" & "show license udi"
sub ShowLicense {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowLicense: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	next if (/^\s+\^$/);
	next if (/^Load for five/);
	next if (/^Time source is/);
	return(0) if (/% no licensable udi in the system/i);	# show udi on old box
	return(0) if (/% license not supported on this device/i);# show lic on old box
	return(0) if (/% incomplete command/i);                 # show lic on old XE box
	return(1) if (/Line has invalid autocommand /);
	return(1) if (/(invalid (input|command) detected|type help or )/i);
	return(-1) if (/(?:%|command)? authorization failed/i);
	return(-1) if (/unable to retrieve license info/i);

	# filter the BS from license broker
	next if (/(renewal attempt|communication attempt):/i);
	next if (/next registration attempt:/i);		# timestamp
	next if (/(period used:|requested time:)/i);		# show lic feature
	if (/(^\s*(evaluation )?period (left|remaining):\s*)\d+/i) {
	    ProcessHistory("COMMENTS","keysort","LICENSE","! $1<limited>\n");
	    next;
	}

	# drop license counts
	next if (/license usage:/i);
	if (/(.*)count status/i) {
	    my($hdr) = $1;
	    my($len) = length($hdr);

	    $hdr =~ s/\s*$//;
	    ProcessHistory("COMMENTS", "keysort", "LICENSE", "! $hdr\n");
	    while (<$INPUT>) {
		tr/\015//d;
		return(0) if (/^$prompt/);

		s/^(.{1,$len}).*/$1/;
		ProcessHistory("COMMENTS", "keysort", "LICENSE", "! $_");
	    }
	    next;
	}

	ProcessHistory("COMMENTS","keysort","LICENSE","! $_");
    }
    ProcessHistory("COMMENTS","keysort","LICENSE","!\n");
    return(0);
}

# This routine parses "showMTU"
sub ShowMTU {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowMTU: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	next if (/^\s+\^$/);
	return(1) if (/Line has invalid autocommand /);
	return(1) if (/(invalid (input|command) detected|type help or )/i);

        if (/System MTU size is (\d+) bytes/) {
            ProcessHistory("COMMENTS","keysort","IO","!MTU: $1\n");
            next;
        }
        if (/System Jumbo MTU size is (\d+) bytes/) {
            ProcessHistory("COMMENTS","keysort","IO","!MTU-Jumbo: $1\n");
            next;
        }
        if (/Routing MTU size is (\d+) bytes/) {
            ProcessHistory("COMMENTS","keysort","IO","!MTU-Routing: $1\n");
            next;
        }
	# XE version
        if (/Global Ethernet MTU is (\d+) bytes./) {
            ProcessHistory("COMMENTS","keysort","IO","!MTU-Global: $1\n");
            next;
        }
        if (/On next reload, (.*)/) {
            ProcessHistory("COMMENTS","keysort","IO","!MTU-Reload: $1\n");
            next;
        }
    }
    ProcessHistory("COMMENTS","keysort","IO","!\n");
    return(0);
}

# This routine parses "show sdm prefer"
sub ShowSDM {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowSDM: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	next if (/^\s+\^$/);
	next if (/^Load for five/);
	next if (/^Time source is/);
	next if (/^Load for five/);
	next if (/^Time source is/);
	return(1) if (/Line has invalid autocommand /);
	return(1) if (/(invalid (input|command) detected|type help or )/i);

        if (/current template is "(.+)" template/) {
            ProcessHistory("COMMENTS","keysort","IO","!SDM Template: $1\n");
            next;
        }
        if (/current template is the (\S+) template/) {
            ProcessHistory("COMMENTS","keysort","IO","!SDM Template: $1\n");
            next;
        }
	# XE version
        if (/This is the (\S+.*) template/) {
            ProcessHistory("COMMENTS","keysort","IO","!SDM Template: $1\n");
            next;
        }
        if (/On next reload, template will be "(.+)" template/) {
            ProcessHistory("COMMENTS","keysort","IO","!SDM Template-Reload: $1\n");
            next;
        }
	if (/(current template is|next reload)/) {
	    ProcessHistory("COMMENTS","keysort","IO","!SDM: $_");
	}
    }
    ProcessHistory("COMMENTS","keysort","IO","!\n");
    return(0);
}

# This routine parses "show redundancy"
sub ShowRedundancy {
    my($INPUT, $OUTPUT, $cmd) = @_;
    my($slave, $slaveslot);
    print STDERR "    In ShowRedundancy: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	next if (/^\s+\^$/);
	next if (/^Load for five/);
	next if (/^Time source is/);
	return(1) if (/Line has invalid autocommand /);
	return(1) if (/(invalid (input|command) detected|type help or )/i);
	# the pager can not be disabled per-session on the PIX
	if (/^(<-+ More -+>)/) {
	    my($len) = length($1);
	    s/^$1\s{$len}//;
	}

	if (/^Version information for secondary in slot (\d+):/) {
	    $slave = " Slave:";
	    $slaveslot = ", slot $1";
	    next;
	}

	/^IOS .* Software \(([A-Za-z0-9_-]*)\), .*Version\s+(.*)$/ &&
	    ProcessHistory("COMMENTS","keysort","F1",
		"!Image:$slave Software: $1, $2\n") && next;
	/^Compiled (.*)$/ &&
	    ProcessHistory("COMMENTS","keysort","F3",
		"!Image:$slave Compiled: $1\n") && next;
    }
    return(0);
}

# This routine parses "show IDprom"
sub ShowIDprom {
    my($INPUT, $OUTPUT, $cmd) = @_;
    my($tmp);

    print STDERR "    In ShowIDprom: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	next if (/^\s+\^$/);
	next if (/^Load for five/);
	next if (/^Time source is/);
	return(1) if (/Line has invalid autocommand /);
	return(1) if (/(invalid (input|command) detected|type help or )/i);
	# the pager can not be disabled per-session on the PIX
	if (/^(<-+ More -+>)/) {
	    my($len) = length($1);
	    s/^$1\s{$len}//;
	}

	/FRU is .(.*)\'/ && ($tmp = $1);
	/Product Number = .(.*)\'/ &&
		ProcessHistory("COMMENTS","keysort","D0",
				"!Catalyst Chassis type: $1, $tmp\n");
	/Serial Number = .([0-9A-Za-z]+)/ &&
		ProcessHistory("COMMENTS","keysort","D1",
				"!Catalyst Chassis S/N: $1\n");
	/Manufacturing Assembly Number = .([-0-9]+)/ && ($tmp = $1);
	/Manufacturing Assembly Revision = .(.*)\'/ && ($tmp .= ", rev " . $1);
	/Hardware Revision = ([0-9.]+)/ &&
		ProcessHistory("COMMENTS","keysort","D2",
				"!Catalyst Chassis assembly: $tmp, ver $1\n");
    }
    return(0);
}

# This routine parses "show install active"
sub ShowInstallActive {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowInstallActive: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	next if (/^\s+\^$/);
	next if (/^Load for five/);
	next if (/^Time source is/);
	return(1) if (/Line has invalid autocommand /);
	return(1) if (/(invalid (input|command) detected|type help or )/i);
	return(-1) if (/(?:%|command)? authorization failed/i);
	# the pager can not be disabled per-session on the PIX
	if (/^(<-+ More -+>)/) {
	    my($len) = length($1);
	    s/^$1\s{$len}//;
	}

	ProcessHistory("COMMENTS","keysort","F5","!Image: $_") && next;
    }
    return(0);
}

# This routine parses "show env all"
sub ShowEnv {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowEnv: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	if (/^$prompt/) { $found_env = 1; last};
	next if (/^(\s*|\s*$cmd\s*)$/);
	next if (/^\s+\^$/);
	next if (/^Load for five/);
	next if (/^Time source is/);
	return(1) if (/Line has invalid autocommand /);
	return(1) if (/(invalid (input|command) detected|type help or )/i);
	return(0) if ($found_env);		# Only do this routine once
	return(-1) if (/(?:%|command)? authorization failed/i);
	# the pager can not be disabled per-session on the PIX
	if (/^(<-+ More -+>)/) {
	    my($len) = length($1);
	    s/^$1\s{$len}//;
	}

	# remove "Fan n RPM is #" on 7201, 7301
	next if (/ RPM is /);

	if (!$E0) {
	    $E0 = 1;
	    ProcessHistory("COMMENTS","keysort","E0","!\n");
	}
	if (/^Arbiter type (\d), backplane type (\S+)/) {
	    if (!$C0) {
		$C0 = 1; ProcessHistory("COMMENTS","keysort","C0","!\n");
	    }
	    ProcessHistory("COMMENTS","keysort","C1",
		"!Enviromental Arbiter Type: $1\n");
	    ProcessHistory("COMMENTS","keysort","A2",
		"!Chassis type: $2 backplane\n");
	    next;
	}
	# AC revision from UBRs and some others fluctuates
	s/is AC Revision [A-F]0\./is AC./;
	/^Power Supply Information$/ && next;
	/^\s*Power Module\s+Voltage\s+Current$/ && next;
	/^\s*(Power [^:\n]+)$/ &&
	    ProcessHistory("COMMENTS","keysort","E1","!Power: $1\n") && next;
	/^\s*(Lower Power .*)/i &&
	    ProcessHistory("COMMENTS","keysort","E2","!Power: $1\n") && next;
	/^\s*(redundant .*)/i &&
	    ProcessHistory("COMMENTS","keysort","E2","!Power: $1\n") && next;
	/^\s*((RPS|power-supply) (\d|is) .*)/i &&
	    ProcessHistory("COMMENTS","keysort","E2","!Power: $1\n") && next;
	/^\s*FAN \d RPM is \d+$/ && next;
	# Fan speed on ASR901
	# Fan 1 Operation: Normal, is running at 40   percent speed
	/^(\s*Fan \d Operation: \S+), .*$/ &&
	    ProcessHistory("COMMENTS","keysort","E3","!FAN: $1\n") && next;

	if (/^\s*((FAN|fan-tray) (\d|is) .*)/i) {
	    my($tmp) = ($1);
	    $tmp =~ s/, \S+ speed setting//;
	    $tmp =~ s/, is running at \d{1,3}\s* percent speed//;
	    ProcessHistory("COMMENTS","keysort","E3","!FAN: $tmp\n");
	    next;
	}
    }
    ProcessHistory("COMMENTS","","","!\n");
    return(0);
}

# This routine parses "show hw-programmable all"
sub ShowHWProgrammable {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowPlatform: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	next if (/^\s+\^$/);
	next if (/^Load for five/);
        next if (/^Time source is/);
	return(0) if (/% incomplete command/i); # every platform is different
	return(1) if (/(invalid (input|command) detected|type help or )/i);
	return(-1) if (/(?:%|command)? authorization failed/i);
	# return(1) if ($type !~ /^12[40]/);
	# the pager can not be disabled per-session on the PIX
	if (/^(<-+ More -+>)/) {
	    my($len) = length($1);
	    s/^$1\s{$len}//;
	}
	/^$/ && next;

	# XXX parsing for show platform, which has CPLD info on some platforms
	#     but is inconsistent across platforms.
	#if (/^(.*) insert time.*$/i) {
	#    my($len) = length($1);
	#    ProcessHistory("PLATFORM","","", "! $1\n");
	#
	#    while (<$INPUT>) {
	#	tr/\015//d;
	#	return(0) if (/^$prompt/);
	#
	#	s/^(.{1,$len}).*/$1/;
	#	ProcessHistory("PLATFORM","","", "! $_");
	#	last if (/^$/);
	#    }
	#    next;
	#}

	ProcessHistory("HWP","","", "! $_");
    }
    ProcessHistory("HWP","","", "!\n");

    return(0);
}

# This routine parses "show rsp chassis-info" for the rsp
# This will create arrays for hw info.
sub ShowRSP {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowRSP: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	next if (/^\s+\^$/);
	return(1) if (/(invalid (input|command) detected|type help or )/i);
	return(-1) if (/(?:%|command)? authorization failed/i);
	# return(1) if ($type !~ /^12[40]/);
	# the pager can not be disabled per-session on the PIX
	if (/^(<-+ More -+>)/) {
	    my($len) = length($1);
	    s/^$1\s{$len}//;
	}
	/^$/ && next;

	/^\s+Chassis model: (\S+)/ &&
	    ProcessHistory("COMMENTS","keysort","D1",
				"!RSP Chassis model: $1\n") &&
	    next;
	/^\s+Chassis S\/N: (.*)$/ &&
	    ProcessHistory("COMMENTS","keysort","D2",
				"!RSP Chassis S/N: $1\n") &&
	    next;
    }

    return(0);
}

# This routine parses "show gsr chassis-info" for the gsr
# This will create arrays for hw info.
sub ShowGSR {
    my($INPUT, $OUTPUT, $cmd) = @_;
    # Skip if this is not a 1200n.
    print STDERR "    In ShowGSR: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	next if (/^\s+\^$/);
	next if (/^Load for five/);
	next if (/^Time source is/);
	next if (/^Load for five/);
	next if (/^Time source is/);
	return(1) if (/(invalid (input|command) detected|type help or )/i);
	return(-1) if (/(?:%|command)? authorization failed/i);
	# return(1) if ($type !~ /^12[40]/);
	# the pager can not be disabled per-session on the PIX
	if (/^(<-+ More -+>)/) {
	    my($len) = length($1);
	    s/^$1\s{$len}//;
	}
	/^$/ && next;

	/^\s+Chassis: type (\S+) Fab Ver: (\S+)/ &&
	    ProcessHistory("COMMENTS","keysort","D1",
				"!GSR Chassis type: $1 Fab Ver: $2\n") &&
	    next;
	/^\s+Chassis S\/N: (.*)$/ &&
	    ProcessHistory("COMMENTS","keysort","D2",
				"!GSR Chassis S/N: $1\n") &&
	    next;
	/^\s+PCA: (\S+)\s*rev: (\S+)\s*dev: \S+\s*HW ver: (\S+)$/ &&
	    ProcessHistory("COMMENTS","keysort","D3",
				"!GSR Backplane PCA: $1, rev $2, ver $3\n") &&
	    next;
	/^\s+Backplane S\/N: (\S+)$/ &&
	    ProcessHistory("COMMENTS","keysort","D4",
				"!GSR Backplane S/N: $1\n") &&
	    next;
    }
    ProcessHistory("COMMENTS","","","!\n");
    return(0);
}

# This routine parses "show boot"
sub ShowBoot {
    my($INPUT, $OUTPUT, $cmd) = @_;
    # Pick up boot variables if 7000/7200/7500/12000/2900/3500;
    # otherwise pick up bootflash.
    print STDERR "    In ShowBoot: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	next if (/^\s+\^$/);
	next if (/^Load for five/);
	next if (/^Time source is/);
	return(1) if (/Line has invalid autocommand /);
	return(1) if (/(invalid (input|command) detected|type help or )/i);
	return(1) if (/Ambiguous command/i);
	return(1) if (/(Open device \S+ failed|Error opening \S+:)/);
	return(-1) if (/(?:%|command)? authorization failed/i);
	# the pager can not be disabled per-session on the PIX
	if (/^(<-+ More -+>)/) {
	    my($len) = length($1);
	    s/^$1\s{$len}//;
	}

	next if /CONFGEN variable/;
	if (!$H0) {
	    $H0 = 1; ProcessHistory("COMMENTS","keysort","H0","!\n");
	}
	if ($type !~ /^(12[04]|7)/) {
	    if ($type !~ /^(29|35)00/) {
		ProcessHistory("COMMENTS","keysort","H2","!BootFlash: $_");
	    } else {
		ProcessHistory("COMMENTS","keysort","H1","!Variable: $_");
	    }
	} elsif (/(variable|register)/) {
	    ProcessHistory("COMMENTS","keysort","H1","!Variable: $_");
	}
    }
    ProcessHistory("COMMENTS","","","!\n");
    return(0);
}

# This routine parses "show flash"
sub ShowFlash {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowFlash: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	# skip if this is 7000, 7200, 7500, 12000, or IOS-XE; else we have
	# redundant data from dir /all slot0:
	return(1) if ($type =~ /^(12[40]|7)/);
	return(1) if ($ios eq "XE");
	next if (/^\s+\^$/);

	next if (/^Load for five/);
	next if (/^Time source is/);
	return(1) if (/Line has invalid autocommand /);
	return(1) if (/(invalid (input|command) detected|type help or )/i);
	return(-1) if (/(?:%|command)? authorization failed/i);
	# the pager can not be disabled per-session on the PIX
	if (/^(<-+ More -+>)/) {
	    my($len) = length($1);
	    s/^$1\s{$len}//;
	}

	# Drop these files entirely.
	/\s+(private-multiple-fs|multiple-fs|LISP-MapCache-IPv\S+|nv_hdr)$/ &&
	    next;

	if (/(dhcp_[^. ]*\.txt|license_evlog|vlan\.dat|sflog|snooping)/ ||
		 /(LOCAL-CA-SERVER(?:[^\s]*))\s*$/ ||
		 /(smart-log\/agentlog|syslog)\s*$/ ||
		 /(log\/(?:ssp_tz\/)?[^. ]+\.log(?:\.[0-9]+\.gz)?)\s*$/) {
	    # filter frequently changing files (dhcp & vlan database, logs) from flash
	    # change from:
	    # 537549598  38354       Feb 19 2019 20:59:32  log/ssp_tz/ssp_tz.log.1.gz
	    # 9          660 Jan 15 2011 20:43:54 vlan.dat
	    # 9          660 Jan 15 2011 20:43:54 +00:00 vlan.dat
	    # to:
	    #                                              log/ssp_tz/ssp_tz.log.1.gz
	    #                                     vlan.dat
	    #                                            vlan.dat
	    if (/(\s*\d+)(\s+[-drwx]+\s+)(\d+)(\s+)(\w+ \d+\s+\d+ \d+:\d+:\d+ .\d+:\d+)/) {
		my($fn, $a, $sz, $c, $dt, $rem) = ($1, $2, $3, $4, $5, $');
		my($fnl, $szl, $dtl) = (length($fn), length($sz), length($dt));
		my($fmt) = "%-". $fnl ."s%s%-". $szl ."s%s%-". $dtl ."s%s";
		$_ = sprintf($fmt, "", $a, "", $c, "", $rem);
	    } elsif (/(\s*\d+)(\s+[-drwx]+\s+)(\d+)(\s+)(\w+ \d+\s+\d+ \d+:\d+:\d+)/) {
		my($fn, $a, $sz, $c, $dt, $rem) = ($1, $2, $3, $4, $5, $');
		my($fnl, $szl, $dtl) = (length($fn), length($sz), length($dt));
		my($fmt) = "%-". $fnl ."s%s%-". $szl ."s%s%-". $dtl ."s%s";
		$_ = sprintf($fmt, "", $a, "", $c, "", $rem);
	    } elsif (/(\s*\d+)(\s+)(\d+)(\s+)(\w+ \d+\s+\d+ \d+:\d+:\d+ .\d+:\d+)/) {
		# System flash directory:
		# File  Length   Name/status
		#   1   12138448  c3640-ik9s-mz.122-40.bin
		my($fn, $a, $sz, $c, $dt, $rem) = ($1, $2, $3, $4, $5, $');
		my($fnl, $szl, $dtl) = (length($fn), length($sz), length($dt));
		my($fmt) = "%-". $fnl ."s%s%-". $szl ."s%s%-". $dtl ."s%s";
		$_ = sprintf($fmt, "", $a, "", $c, "", $rem);
	    } elsif (/(\s*\d+)(\s+)(\d+)(\s+)(\w+ \d+\s+\d+ \d+:\d+:\d+)/) {
		my($fn, $a, $sz, $c, $dt, $rem) = ($1, $2, $3, $4, $5, $');
		my($fnl, $szl, $dtl) = (length($fn), length($sz), length($dt));
		my($fmt) = "%-". $fnl ."s%s%-". $szl ."s%s%-". $dtl ."s%s";
		$_ = sprintf($fmt, "", $a, "", $c, "", $rem);
	    }
	    /\s+(\S+)\s*$/ &&
		ProcessHistory("FLASH","keysort","$1","!Flash: $_") && next;
	} elsif (/(running-config-archive-)\S+\s*$/) {
	    # filter config archives from flash
	    # change from:
	    # 9          660 Jan 15 2011 20:43:54 running-config-archive-Jul--1-16-50-27.123-113
	    # 9          660 Jan 15 2011 20:43:54 +00:00 running-config-archive-Jul--1-16-50-27.123-113
	    # to:
	    #                                     running-config-archive-<removed>
	    #                                     running-config-archive-<removed>
	    my($arc) = $1;
	    if (/(\s*\d+)(\s+[-drwx]+\s+)(\d+)(\s+)(\w+ \d+\s+\d+ \d+:\d+:\d+ .\d+:\d+)/) {
		my($fn, $a, $sz, $c, $dt, $rem) = ($1, $2, $3, $4, $5, $');
		my($fnl, $szl, $dtl) = (length($fn), length($sz), length($dt));
		my($fmt) = "%-". $fnl ."s%s%-". $szl ."s%s%-". $dtl ."s%s%s\n";
		$_ = sprintf($fmt, "", $a, "", $c, "", $arc , "<removed>");
	    } elsif (/(\s*\d+)(\s+[-drwx]+\s+)(\d+)(\s+)(\w+ \d+\s+\d+ \d+:\d+:\d+)/) {
		my($fn, $a, $sz, $c, $dt, $rem) = ($1, $2, $3, $4, $5, $');
		my($fnl, $szl, $dtl) = (length($fn), length($sz), length($dt));
		my($fmt) = "%-". $fnl ."s%s%-". $szl ."s%s%-". $dtl ."s%s%s\n";
		$_ = sprintf($fmt, "", $a, "", $c, "", $arc, "<removed>");
	    } elsif (/(\s*\d+)(\s+)(\d+)(\s+)(\w+ \d+\s+\d+ \d+:\d+:\d+ .\d+:\d+)/) {
		my($fn, $a, $sz, $c, $dt, $rem) = ($1, $2, $3, $4, $5, $');
		my($fnl, $szl, $dtl) = (length($fn), length($sz), length($dt));
		my($fmt) = "%-". $fnl ."s%s%-". $szl ."s%s%-". $dtl ."s%s%s\n";
		$_ = sprintf($fmt, "", $a, "", $c, "", $arc, "<removed>");
	    } elsif (/(\s*\d+)(\s+)(\d+)(\s+)(\w+ \d+\s+\d+ \d+:\d+:\d+)/) {
		my($fn, $a, $sz, $c, $dt, $rem) = ($1, $2, $3, $4, $5, $');
		my($fnl, $szl, $dtl) = (length($fn), length($sz), length($dt));
		my($fmt) = "%-". $fnl ."s%s%-". $szl ."s%s%-". $dtl ."s%s%s\n";
		$_ = sprintf($fmt, "", $a, "", $c, "", $arc, "<removed>");
	    }
	    /\s+(\S+)\s*$/ &&
		ProcessHistory("FLASH","keysort","$1","!Flash: $_") && next;
	} elsif (/^(\s*\d+)(\s+[-drwx]+\s+\d+\s+\w+ \d+\s+\d+ \d+:\d+:\d+ .\d+:\d+\s+)(\S+)/ ||
		 /^(\s*\d+)(\s+[-drwx]+\s+\d+\s+\w+ \d+\s+\d+ \d+:\d+:\d+\s+)(\S+)/ ||
		 /^(\s*\d+)(\s+\d+\s+\w+ \d+\s+\d+ \d+:\d+:\d+ .\d+:\d+\s+)(\S+)/ ||
		 /^(\s*\d+)(\s+\d+\s+\w+ \d+\s+\d+ \d+:\d+:\d+\s+)(\S+)/) {
	    my($fmt) = "%-". length($1) ."s%s%s\n";
	    $_ = sprintf($fmt, "", $2, $3);
	    ProcessHistory("FLASH","keysort","$3","!Flash: $_") && next;
        }

	if (/(\d+) bytes (available|total) \((\d+) bytes (free|used)(\/\s+% free)?\)/) {
	    my($avail);
	    my($preamble) = "";
	    if ($2 eq "available") {
		$avail = $1;
	    } else {
		$preamble = "$1 bytes total";
		if ($4 eq "free") {
		    $avail = $3;
		} else {
		    $avail = $1 - $3;
		}
	    }
	    if ($avail >= (1024 * 1024 * 1024)) {
		$avail = int($avail / (1024 * 1024 * 1024));
		$_ = "$avail GB free\n";
	    } elsif ($avail >= (1024 * 1024)) {
		$avail = int($avail / (1024 * 1024));
		$_ = "$avail MB free\n";
	    } elsif ($avail >= (1024)) {
		$avail = int($avail / 1024);
		$_ = "$avail KB free\n";
	    } elsif ($avail > 0) {
		$_ = "< 1KB free\n";
	    } else {
		$_ = "0 bytes free\n";
	    }
	    if (length($preamble)) {
		chomp($_);
		$_ = "$preamble ($_)\n";
	    }
	}
	ProcessHistory("FLASH","","","!Flash: $_");
    }
    ProcessHistory("","","","!\n");
    return;
}

# This routine parses "dir /all ((disk|slot)N|bootflash|nvram):"
sub DirSlotN {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In DirSlotN: $_" if ($debug);

    my($dev) = (/\s([^\s]+):/);

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	next if (/^\s+\^$/);
	next if (/^Load for five/);
	next if (/^Time source is/);
	return(1) if (/Line has invalid autocommand /);
	return(1) if (/(invalid (input|command) detected|type help or )/i);
	return(1) if (/(No such device|Error Sending Request)/i);
	return(1) if (/\%Error: No such file or directory/);
	return(1) if (/No space information available/);
	# Corrupt flash
	/\%Error calling getdents / &&
	    ProcessHistory("FLASH","","","!Flash: $dev: $_") && next;
	return(-1) if (/\%Error calling/);
	return(-1) if (/(: device being squeezed|ATA_Status time out)/i); # busy
	return(-1) if (/\%Error opening \S+:\S+ \(Device or resource busy\)/i);
	return(-1) if (/(?:%|command)? authorization failed/i);
	return(1) if (/(Open device \S+ failed|Error opening \S+:)/);
	# the pager can not be disabled per-session on the PIX
	if (/^(<-+ More -+>)/) {
	    my($len) = length($1);
	    s/^$1\s{$len}//;
	}

	# skip dir sup-bootflash if dir sup-bootdisk was successful, duplicates
	if ($cmd =~ / sup-bootdisk/) {
	    $supbootdisk++;
	} elsif ($supbootdisk && $cmd =~ / sup-bootflash/) {
	    return(0);
	}

	# Drop LISP cache.
	/\s+LISP-MapCache-IPv\S+$/ && next;

	# Filter internal file used by ISSU (In-Service Software Upgrade)
	# on dual RP ASR systems
	next if (/\.issu_loc_lock\s*$/);

	# vASA nonsense
	# 9 file(s) total size: 252854822 bytes
	next if (/\d+ file\S+ total size: \d+ bytes/i);

	# filter frequently changing files (dhcp & vlan database)
	# change from:
	#    9  -rw-         660  Jan 15 2011 20:43:54 vlan.dat
	#    9  -rw-         660  Jan 15 2011 20:43:54 +00:00  vlan.dat
	# to:
	#       -rw-                                   vlan.dat
	#       -rw-                                           vlan.dat
	if (/(dhcp_[^. ]*\.txt|vlan\.dat|sflog|snooping|syslog)\s*$/ ||
	    /(tracelogs|throughput_monitor_params|underlying-config)\s*$/) {
	    if (/(\s*\d+\s+)(\S+\s+)(\d+)(\s+)(\w+ \d+\s+\d+ \d+:\d+:\d+ .\d+:\d+)/) {
		my($fn, $a, $sz, $c, $dt, $rem) = ($1, $2, $3, $4, $5, $');
		my($fnl, $szl, $dtl) = (length($fn), length($sz), length($dt));
		my($fmt) = "%s%-". $szl ."s%s%-". $dtl ."s%s";
		$_ = sprintf($fmt, $a, "", $c, "", $rem);
	    } elsif (/(\s*\d+\s+)(\S+\s+)(\d+)(\s+)(\w+ \d+\s+\d+ \d+:\d+:\d+)/) {
		my($fn, $a, $sz, $c, $dt, $rem) = ($1, $2, $3, $4, $5, $');
		my($fnl, $szl, $dtl) = (length($fn), length($sz), length($dt));
		my($fmt) = "%s%-". $szl ."s%s%-". $dtl ."s%s";
		$_ = sprintf($fmt, $a, "", $c, "", $rem);
	    } elsif (/(\s*\d+\s+)(\S+\s+)(\d+)(\s+<no date>)/i) {
		# 32771  -rw-            24520                    <no date>  underlying-config
		my($fn, $a, $sz, $dt, $rem) = ($1, $2, $3, $4, $');
		my($fnl, $szl) = (length($fn), length($sz));
		my($fmt) = "%s%-". $szl ."s%s%s";
		$_ = sprintf($fmt, $a, "", $dt, $rem);
	    }
	    /\s+(\S+)\s*$/ &&
		ProcessHistory("FLASH","keysort","$1","!Flash: $dev: $_") &&
		next;
	} elsif (/(running-config-archive-)\S+\s*$/) {
	    my($arc) = $1;

	    # filter frequently changing files of the config archive feature
	    # change from:
	    #    9  -rw-         660  Jan 15 2011 20:43:54 running-config-archive-Jul--1-16-50-27.123-113
	    #    9  -rw-         660  Jan 15 2011 20:43:54 +00:00  running-config-archive-Jul--1-16-50-27.123-113
	    # to:
	    #       -rw-                                   running-config-archive-Jul--1-16-50-27.123-113
	    #       -rw-                                           running-config-archive-Jul--1-16-50-27.123-113
	    if (/(\s*\d+\s+)(\S+\s+)(\d+)(\s+)(\w+ \d+\s+\d+ \d+:\d+:\d+ .\d+:\d+)/) {
		my($fn, $a, $sz, $c, $dt, $rem) = ($1, $2, $3, $4, $5, $');
		my($fnl, $szl, $dtl) = (length($fn), length($sz), length($dt));
		my($fmt) = "%s%-". $szl ."s%s%-". $dtl ."s%s%s\n";
		$_ = sprintf($fmt, $a, "", $c, "", $arc, "<removed>");
	    } elsif (/(\s*\d+\s+)(\S+\s+)(\d+)(\s+)(\w+ \d+\s+\d+ \d+:\d+:\d+)/) {
		my($fn, $a, $sz, $c, $dt, $rem) = ($1, $2, $3, $4, $5, $');
		my($fnl, $szl, $dtl) = (length($fn), length($sz), length($dt));
		my($fmt) = "%s%-". $szl ."s%s%-". $dtl ."s%s%s\n";
		$_ = sprintf($fmt, $a, "", $c, "", $arc, "<removed>");
	    }
	    /\s+(\S+)\s*$/ &&
		ProcessHistory("FLASH","keysort","$1","!Flash: $dev: $_") &&
		next;
	} else {
	    # drop file number (from the various formats):
	    #     3  -rw-             1011                    <no date>  ifIndex-table
	    #    9  -rw-         660  Jan 15 2011 20:43:54 vlan.dat
	    #   16  -rw-             5437  Jan 16 2016 02:22:32 +00:00  licenses
	    #  114    -rwx  92           13:22:08 Aug 15 2019  .boot_string (ASA)
	    if (/(\s*\d+\s+)(\S+\s+\d+\s+\w+ \d+\s+\d+ \d+:\d+:\d+ .\d+:\d+)/ ||
	        /(\s*\d+\s+)(\S+\s+\d+\s+\w+ \d+\s+\d+ \d+:\d+:\d+)/ ||
	        /(\s*\d+\s+)(\S+\s+\d+\s+<no date>\s+\S+)/ ||
	        /(\s*\d+\s+)(\S+\s+\d+\s+\d+:\d+:\d+ \w+ \d+\s+\d+\s+\S+)/) {
		#my($fn, $a, $rem) = ($1, $2, $');
		#my($fnl) = length($fn);
		#my($fmt) = "%-". $fnl ."s%s%s\n";
		#$_ = sprintf($fmt, "", $a, $rem);
		$_ = $2 . $';
		/\s+(\S+)\s*$/ &&
		    ProcessHistory("FLASH","keysort","$1","!Flash: $dev: $_") &&
		    next;
	    }
	}

	# XE: 822083584 bytes total (821081600 bytes free)
	if (/^\s*(\d+) bytes total\s+\((\d+) bytes free\)/i) {
	    ProcessHistory("FLASH","","","!Flash: $dev: " .
			   diskszsummary($1, $2) . "\n");
	    next;
	}
	# vASA: 8571076608 bytes total (8306561024 bytes free/96% free)
	if (/^\s*(\d+) bytes total \((\d+) bytes free\/\d+% free\)/) {
	    ProcessHistory("FLASH","","","!Flash: $dev: " .
			   diskszsummary($1, $2) . "\n");
	    next;
	}

	ProcessHistory("FLASH","","","!Flash: $dev: $_");
    }
    ProcessHistory("","","","!\n");
    return(0);
}

# This routine parses "show controllers"
sub ShowContAll {
    my($INPUT, $OUTPUT, $cmd) = @_;
    my($INT);
    # Skip if this is a 70[01]0, 7500, or 12000.
    print STDERR "    In ShowContAll: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	next if (/^\s+\^$/);
	next if (/^Load for five/);
	next if (/^Time source is/);
	return(1) if (/(invalid (input|command) detected|type help or )/i);
	# return(1) if ($type =~ /^(12[40]|7[05])/);
	return(-1) if (/(?:%|command)? authorization failed/i);
	# the pager can not be disabled per-session on the PIX
	if (/^(<-+ More -+>)/) {
	    my($len) = length($1);
	    s/^$1\s{$len}//;
	}

	if (/^Interface ([^ \n(]*)/) { $INT = "$1, "; next; }
	/^(BRI unit \d)/ &&
	    ProcessHistory("INT","","","!Interface: $1\n") && next;
	/^LANCE unit \d, NIM/ &&
	    ProcessHistory("INT","","","!Interface: $_") && next;
	/^(LANCE unit \d)/ &&
	    ProcessHistory("INT","","","!Interface: $1\n") && next;
	/(Media Type is \S+),/ &&
	    ProcessHistory("INT","","","!\t$1\n");
	if (/(M\dT[^ :]*:) show controller:$/) {
	    my($ctlr) = $1;
	    $_ = <$INPUT>; tr/\015//d; s/ subunit \d,//;
	    ProcessHistory("INT","","","!Interface: $ctlr $_");
	}
	if (/^(\S+) : show controller:$/) {
	    my($ctlr) = $1;
	    $_ = <$INPUT>; tr/\015//d; s/ subunit \d,//;
	    ProcessHistory("INT","","","!Interface: $ctlr: $_");
	}
	/^(HD unit \d), idb/ &&
	    ProcessHistory("INT","","","!Interface: $1\n") && next;
	/^HD unit \d, NIM/ &&
	    ProcessHistory("INT","","","!Interface: $_") && next;
	/^buffer size \d+  HD unit \d, (.*)/ &&
	    ProcessHistory("INT","","","!\t$1\n") && next;
	/^AM79970 / && ProcessHistory("INT","","","!Interface: $_") && next;
	/^buffer size \d+  (Universal Serial: .*)/ &&
	    ProcessHistory("INT","","","!\t$1\n") && next;
	# Remove dynamic addresses like:
	# !Interface: FastEthernet0/0, GT96K FE ADDR: 62AFB684, FASTSEND: 6 1579E4C, MCI_INDEX: 0
	/^ *Hardware is (.*?)($| ADDR: .*| at 0x.*)/ &&
	    ProcessHistory("INT","","","!Interface: $INT$1\n") && next;
	/^Hardware is (.*)/ &&
	    ProcessHistory("INT","","","!Interface: $INT$1\n") && next;
	/^(QUICC Serial unit \d),/ &&
	    ProcessHistory("INT","","","!$1\n") && next;
	/^QUICC Ethernet .*/ &&
	    ProcessHistory("INT","","","!$_") && next;
	/^DTE .*\.$/ && next;
	/^(cable type :.*),/ &&
	    ProcessHistory("INT","","","!\t$1\n") && next;
	/^(.* cable.*), received clockrate \d+$/ &&
	    ProcessHistory("INT","","","!\t$1\n") && next;
	/^.* cable.*$/ &&
	    ProcessHistory("INT","","","!\t$_") && next;
    }
    return(0);
}

# This routine parses "show controllers cbus"
# Some of this is printed out in ShowDiagbus.
sub ShowContCbus {
    my($INPUT, $OUTPUT, $cmd) = @_;
    my($interface, $slot);
    # Skip if this is not a 7000 or 7500.
    print STDERR "    In ShowContCbus: $_" if ($debug);

    while (<$INPUT>) {
	my(%board, %hwver);
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	next if (/^\s+\^$/);
	next if (/^Load for five/);
	next if (/^Time source is/);
	return(1) if (/(invalid (input|command) detected|type help or )/i);
	#return(1) if ($type !~ /^7[05]0/);
	return(-1) if (/(?:%|command)? authorization failed/i);
	# the pager can not be disabled per-session on the PIX
	if (/^(<-+ More -+>)/) {
	    my($len) = length($1);
	    s/^$1\s{$len}//;
	}

	if (/^\s*slot(\d+): ([^,]+), hw (\S+), sw (\S+), ccb/) {
	    $slot = $1;
	    $board{$slot} = $2;
	    $hwver{$slot} = $3;
	    $hwucode{$slot} = $4;
	} elsif (/^\s*(\S+) (\d+), hardware version (\S+), microcode version (\S+)/) {
	    $slot = $2;
	    $board{$slot} = $1;
	    $hwver{$slot} = $3;
	    $hwucode{$slot} = $4;
	} elsif (/(Microcode .*)/) {
	    $ucode{$slot} = $1;
	} elsif (/(software loaded .*)/) {
	    $ucode{$slot} = $1;
	} elsif (/(\d+) Kbytes of main memory, (\d+) Kbytes cache memory/) {
	    $hwmemd{$slot} = $1;
	    $hwmemc{$slot} = $2;
	} elsif (/byte buffers/) {
	    chop;
	    s/^\s*//;
	    $hwbuf{$slot} = $_;
	} elsif (/Interface (\d+) - (\S+ \S+),/) {
	    $interface = $1;
	    ProcessHistory("HW","","",
		"!\n!Int $interface: in slot $slot, named $2\n"); next;
	} elsif (/(\d+) buffer RX queue threshold, (\d+) buffer TX queue limit, buffer size (\d+)/) {
	    ProcessHistory("HW","","","!Int $interface: rxq $1, txq $2, bufsize $3\n");
	    next;
	}
    }
    return(0);
}

# This routine parses "show debug"
sub ShowDebug {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowDebug: $_" if ($debug);
    my($lines) = 0;

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	next if (/^\s+\^$/);
	next if (/^Load for five/);
	next if (/^Time source is/);
	return(1) if (/Line has invalid autocommand /);
	return(1) if (/(invalid (input|command) detected|type help or )/i);
	return(-1) if (/(?:%|command)? authorization failed/i);
	# ASAv produce this error occasionally
	return(-1) if (/unable to retrieve licensing debug info/i);
	# the pager can not be disabled per-session on the PIX
	if (/^(<-+ More -+>)/) {
	    my($len) = length($1);
	    s/^$1\s{$len}//;
	}

	/Load for / && next;
	/^Time source is / && next;
	/^No matching debug flags set$/ && next;
	/^No debug flags set$/ && next;
	ProcessHistory("COMMENTS","keysort","J1","!DEBUG: $_");
	$lines++;
    }
    if ($lines) {
	ProcessHistory("COMMENTS","keysort","J0","!\n");
    }
    return(0);
}

# This routine parses "show diagbus"
# This will create arrays for hw info.
sub ShowDiagbus {
    my($INPUT, $OUTPUT, $cmd) = @_;
    my($board, $slot);
    # Skip if this is not a 7000, 70[01]0, or 7500.
    print STDERR "    In ShowDiagbus: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	#return(1) if ($type !~ /^7[05]/);
	next if (/^\s+\^$/);
	next if (/^Load for five/);
	next if (/^Time source is/);
	return(1) if (/Line has invalid autocommand /);
	return(1) if (/(invalid (input|command) detected|type help or )/i);
	return(-1) if (/(?:%|command)? authorization failed/i);
	# the pager can not be disabled per-session on the PIX
	if (/^(<-+ More -+>)/) {
	    my($len) = length($1);
	    s/^$1\s{$len}//;
	}

	if (/^\s*Slot (\d+):/i) {
	    $slot = $1;
	    next;
	} elsif (/^\s*Slot (\d+) \(virtual\):/i) {
	    $slot = $1;
	    next;
	} elsif (/^\s*(.*Processor.*|.*controller|.*controler|.*Chassis Interface)(, FRU\s?:.*)?, HW rev (\S+), board revision (\S+)/i) {
	    $board = $1;
	    my($hwver) = $3;
	    my($boardrev) = $4;
	    if ($board =~ /Processor/) {
		if ($board =~ /7000 Route\/Switch/) {
		    $board = "RSP7000";
		} elsif ($board =~ /Route\/Switch Processor (\d)/) {
		    $board = "RSP$1";
		} elsif ($board =~ /Route/) {
		    $board = "RP";
		} elsif ($board =~ /Silicon Switch/) {
		    $board = "SSP";
		} elsif ($board =~ /Switch/) {
		    $board = "SP";
		    $board = "SSP $sspmem" if $ssp;
		} elsif ($board =~ /ATM/) {
		    $board = "AIP";
		}
	    } elsif ($board =~ /(.*) controller/i) {
		$board = $1;
	    }
	    # hwucode{$slot} defined in ShowContCbus
	    if (defined($hwucode{$slot})) {
		ProcessHistory("SLOT","","","!\n!Slot $slot/$board: hvers $hwver rev $boardrev ucode $hwucode{$slot}\n");
	    } else {
		ProcessHistory("SLOT","","","!\n!Slot $slot/$board: hvers $hwver rev $boardrev\n");
	    }
	    # These are also from the ShowContCbus
	    ProcessHistory("SLOT","","","!Slot $slot/$board: $ucode{$slot}\n") if (defined $ucode{$slot});
	    ProcessHistory("SLOT","","","!Slot $slot/$board: memd $hwmemd{$slot}, cache $hwmemc{$slot}\n")
	    if ((defined $hwmemd{$slot}) && (defined $hwmemc{$slot}));
	    ProcessHistory("SLOT","","","!Slot $slot/$board: $hwbuf{$slot}\n") if (defined $hwbuf{$slot});
	    next;
	}
	/Serial number: (\S+)\s*Part number: (\S+)/ &&
	    ProcessHistory("SLOT","","",
			"!Slot $slot/$board: part $2, serial $1\n") &&
	    next;
	/^\s*Controller Memory Size: (.*)$/ &&
	    ProcessHistory("SLOT","","","!Slot $slot/$board: $1\n") &&
	    next;
	if (/PA Bay (\d) Information/) {
	    my($pano) = $1;
	    if ("PA" =~ /$board/) {
		my($s,$c) = split(/\//,$board);
		$board = "$s/$c/PA $pano";
	    } else {
		$board =~ s/\/PA \d//;
		$board = "$board/PA $pano";
	    }
	    next;
	}
	/\s+(.*) (IP|PA), (\d) ports?,( \S+,)? (FRU\s?: )?(\S+)/ &&
	    ProcessHistory("SLOT","","","!Slot $slot/$board: type $6, $3 ports\n") &&
	    next;
	/\s+(.*) (IP|PA)( \(\S+\))?, (\d) ports?/ &&
	    ProcessHistory("SLOT","","","!Slot $slot/$board: type $1$3, $4 ports\n") &&
	    next;
	/^\s*HW rev (\S+), Board revision (\S+)/ &&
	    ProcessHistory("SLOT","","","!Slot $slot/$board: hvers $1 rev $2\n") &&
	    next;
	/Serial number: (\S+)\s*Part number: (\S+)/ &&
	    ProcessHistory("SLOT","","","!Slot $slot/$board: part $2, serial $1\n") && next;
    }
    return(0);
}

# This routine parses "show diag" for the gsr, 7200, 3700, 3600, 2600.
# This will create arrays for hw info.
sub ShowDiag {
    my($INPUT, $OUTPUT, $cmd) = @_;
    my($fn, $slot, $WIC);
    print STDERR "    In ShowDiag: $_" if ($debug);

    while (<$INPUT>) {
REDUX:	tr/\015//d;
	if (/^$prompt/) { $found_diag = 1; last};
	next if (/^(\s*|\s*$cmd\s*)$/);
	return(1) if (/Line has invalid autocommand /);
	next if (/^\s+\^\s*$/);
	next if (/^Load for five/);
	next if (/^Time source is/);
	return(1) if (/(invalid (input|command) detected|type help or )/i);
	return(0) if ($found_diag);		# Only do this routine once
	return(-1) if (/(?:%|command)? authorization failed/i);
	/^$/ && next;
	# the pager can not be disabled per-session on the PIX
	if (/^(<-+ More -+>)/) {
	    my($len) = length($1);
	    s/^$1\s{$len}//;
	}

	s/Port Packet Over SONET/POS/;
	if (/^\s*SLOT\s+(\d+)\s+\((.*)\): (.*)/) {
	    $slot = $1;
	    ProcessHistory("SLOT","","","!\n");
	    ProcessHistory("SLOT","keysort","A","!Slot $slot: $3\n");
	    next;
	}
	if (/^\s*NODE\s+(\S+) : (.*)/) {
	    $slot = $1;
	    ProcessHistory("SLOT","","","!\n");
	    ProcessHistory("SLOT","keysort","A","!Slot $slot: $2\n");
	    next;
	}
	if (/^\s*PLIM\s+(\S+) : (.*)/) {
	    $slot = $1 . " PLIM";
	    ProcessHistory("SLOT","","","!\n");
	    ProcessHistory("SLOT","keysort","A","!Slot $slot: $2\n");
	    next;
	}
	if (/^\s*RACK\s+(\S+) : (.*)/) {
	    $slot = "Rack/" . $1;
	    ProcessHistory("SLOT","","","!\n");
	    ProcessHistory("SLOT","keysort","A","!Slot $slot: $2\n");
	    next;
	}
	if (/^\s+MAIN:\s* type \S+,\s+(.*)/) {
	    my($part) = $1;
	    $_ = <$INPUT>;
	    if (/^\s+(HW version|Design Release) (\S+)\s+S\/N (\S+)/i) {
		ProcessHistory("SLOT","keysort","AM","!Slot $slot/MAIN: part $part, serial $3\n");
		ProcessHistory("SLOT","keysort","AM","!Slot $slot/MAIN: hvers $2\n");
	    } else {
		ProcessHistory("SLOT","keysort","AM","!Slot $slot/MAIN: part $part\n");
		goto REDUX;
	    }
	    next;
	}
	if (/^\s+MAIN:\s* board type \S+$/) {
	    $_ = <$INPUT>;
	    tr/\015//d;
	    if (/^\s+(.+)$/) {
		my($part) = $1;
		$_ = <$INPUT>;
		tr/\015//d;
		if (/^\s+dev (.*)$/) {
		    my($dev) = $1;
		    $_ = <$INPUT>;
		    if (/^\s+S\/N (\S+)/) {
			ProcessHistory("SLOT","keysort","AM","!Slot $slot/MAIN: part $part, dev $dev, serial $1\n");
		    } else {
			ProcessHistory("SLOT","keysort","AM","!Slot $slot/MAIN: part $part, dev $dev\n");
			goto REDUX;
		   }
		} else {
		    ProcessHistory("SLOT","keysort","AM","!Slot $slot/MAIN: part $part\n");
		    goto REDUX;
		}
	    } else {
		goto REDUX;
	    }
	    next;
	}
	if (/^c3700\s+(io-board|mid-plane)/i) {
	    $slot = $1;
	    ProcessHistory("SLOT","","","!\n");
	    ProcessHistory("SLOT","keysort","A","!Slot $slot: part $1\n");
	    next;
	}
	if (/ Engine:\s+(.*)/) {
	    ProcessHistory("SLOT","keysort","AE","!Slot $slot/Engine: $1\n");
	}
	if (/FRU:\s+Linecard\/Module:\s+(\S+)/) {
	    ProcessHistory("SLOT","keysort","AF","!Slot $slot/FRU: Linecard/Module: $1\n");
	    next;
	}
	if (/\s+Processor Memory:\s+(\S+)/) {
	    ProcessHistory("SLOT","keysort","AF","!Slot $slot/FRU: Processor Memory: $1\n");
	    next;
	}
	if (/\s+Packet Memory:\s+(\S+)/) {
	    ProcessHistory("SLOT","keysort","AF","!Slot $slot/FRU: Packet Memory: $1\n");
	    next;
	}
	if (/\s+Route Memory:\s+(\S+)/) {
	    ProcessHistory("SLOT","keysort","AF","!Slot $slot/FRU: Route Memory: $1\n");
	    next;
	}
	if (/^\s+PCA:\s+(.*)/) {
	    my($part) = $1;
	    $_ = <$INPUT>;
	    if (/^\s+(HW version|design release) (\S+)\s+S\/N (\S+)/i) {
		ProcessHistory("SLOT","keysort","C1","!Slot $slot/PCA: part $part, serial $3\n");
		ProcessHistory("SLOT","keysort","C2","!Slot $slot/PCA: hvers $2\n");
	    } else {
		ProcessHistory("SLOT","keysort","C1","!Slot $slot/PCA: part $part\n");
		goto REDUX;
	    }
	    next;
	}
	if (/^\s+MBUS: .*\)\s+(.*)/) {
	    my($tmp) = "!Slot $slot/MBUS: part $1";
	    $_ = <$INPUT>;
	    /^\s+HW version (\S+)\s+S\/N (\S+)/ &&
		ProcessHistory("SLOT","keysort","MB1","$tmp, serial $2\n") &&
		ProcessHistory("SLOT","keysort","MB2","!Slot $slot/MBUS: hvers $1\n");
	    next;
	}
	if (/^\s+MBUS Agent Software version (.*)/) {
	    ProcessHistory("SLOT","keysort","MB3","!Slot $slot/MBUS: software $1\n");
	    next;
	}
	if (/^\s+PLD: (.*)/) {
	    ProcessHistory("SLOT","keysort","P","!Slot $slot/PLD: $1\n");
	    next;
	}
	if (/^\s+MONLIB: (.*)/) {
	    ProcessHistory("SLOT","keysort","Q","!Slot $slot/MONLIB: $1\n");
	    next;
	}
	if (/^\s+ROM Monitor version (.*)/) {
	    ProcessHistory("SLOT","keysort","R","!Slot $slot/ROM Monitor: version $1\n");
	    next;
	}
	if (/^\s+ROMMON: Version (.*)/) {
	    ProcessHistory("SLOT","keysort","R","!Slot $slot/ROMMON: version $1\n");
	    next;
	}
	if (/^\s+Fabric Downloader version used (.*)/) {
	    ProcessHistory("SLOT","keysort","Z","!Slot $slot/Fabric Downloader: version $1\n");
	    next;
	}
	if (/^\s+DRAM size: (\d+)/) {
	    my($dram) = $1 / 1048576;
	    $_ = <$INPUT>;
	    if (/^\s+FrFab SDRAM size: (\d+)/) {
		ProcessHistory("SLOT","keysort","MB4","!Slot $slot/MBUS: $dram Mbytes DRAM, "
			   . $1 / 1024 . " Kbytes SDRAM\n");
	    } else {
		ProcessHistory("SLOT","keysort","MB4","!Slot $slot/MBUS: $dram Mbytes DRAM\n");
		goto REDUX;
	    }
	    next;
	}
	# 7200, 3800, 3600, 2600, and 1700 stuff
	if (/^(Slot)\s+(\d+(\/\d+)?):/
	    || /^\s+(PVDM|WIC|VIC|WIC\/VIC|WIC\/VIC\/HWIC) Slot (\d):/
	    || /^(Encryption AIM) (\d):/
	    || /^(AIM Module in slot:) (\d)/) {
	    if ($1 eq "PVDM") {
		$WIC = "/$2";
	    } elsif ($1 eq "WIC") {
		$WIC = "/$2";
	    } elsif ($1 eq "VIC") {
		$WIC = "/$2";
	    } elsif ($1 eq "WIC/VIC") {
		$WIC = "/$2";
	    } elsif ($1 eq "WIC/VIC/HWIC") {
		$WIC = "/$2";
	    } elsif ($1 eq "DSP") {
		$WIC = "/$2";
	    } elsif ($1 eq "Encryption AIM") {
		$slot = "$2";
		$WIC = undef;
		ProcessHistory("SLOT","","","!\n");
		ProcessHistory("SLOT","keysort","B","!Slot $slot: type $1\n");
		next;
	    } elsif ($1 eq "AIM Module in slot:") {
		$slot = "AIM $2";
		$WIC = undef;
		ProcessHistory("SLOT","","","!\n");
		ProcessHistory("SLOT","keysort","B",
			       "!Slot $slot: type AIM Module\n");
		next;
	    } else {
		$slot = $2;
		$WIC = undef;
	    }
	    $_ = <$INPUT>; tr/\015//d;

	    # clean up hideous 7200/etc formats to look more like 7500 output
	    s/Fast-ethernet on C7200 I\/O card/FE-IO/;
	    s/ with MII or RJ45/-TX/;
	    s/Fast-ethernet /100Base/; s/[)(]//g;
	    s/intermediate reach/IR/i;

	    ProcessHistory("SLOT","","","!\n");
	    /\s+(.*) port adapter,?\s+(\d+)\s+/i &&
		ProcessHistory("SLOT","keysort","B",
			       "!Slot $slot: type $1, $2 ports\n") && next;
	    # I/O controller with no interfaces
	    /\s+(.*)\s+port adapter\s*$/i &&
		ProcessHistory("SLOT","keysort","B",
			       "!Slot $slot: type $1, 0 ports\n") && next;
	    /\s+(.*)\s+daughter card(.*)$/ &&
		ProcessHistory("SLOT","keysort","B",
			       "!Slot $slot$WIC: type $1$2\n") && next;
	    /\s+(FT1)$/ &&
		ProcessHistory("SLOT","keysort","B",
			       "!Slot $slot$WIC: type $1\n") && next;
	    # AS5300/5400 handling
	    /^Hardware is\s+(.*)$/i &&
		ProcessHistory("SLOT","keysort","B","!Slot $slot: type $1\n")
		&& next;
	    /^DFC type is\s+(.*)$/i &&
		ProcessHistory("SLOT","keysort","B","!Slot $slot: type $1\n")
		&& next;
	    #
	    # handle WICs lacking "daughter card" in the 2nd line of their
	    # show diag o/p
	    if (length($WIC)) {
		s/^\s+//;
		ProcessHistory("SLOT","keysort","B","!Slot $slot$WIC: type $_");
	    }
	    next;
	} elsif (/^\s+(.* (DSP) Module) Slot (\d):/) {
	    # The 1760 (at least) has yet another format...where it has two
	    # dedicated DSP slots, and thus two slot 0s.
	    my($TYPE) = $1;
	    $WIC = "/$3";
	    ProcessHistory("SLOT","","","!\n");
	    ProcessHistory("SLOT","keysort","B",
					"!Slot $slot$WIC: type $TYPE\n");
	    next;
	}
	# yet another format.  seen on 2600s w/ 12.1, but appears to be all
	# 12.1, including 7200s & 3700s.  Sometimes the PCB serial appears
	# before the hardware revision.
	if (/(pcb serial number|hardware revision)\s+:\s+(\S+)$/i) {
	    my($hw, $pn, $rev, $sn);
	    if ($1 =~ /^pcb/i) {
		$sn = $2;
	    } else {
		$hw = $2;
	    }
	    while (<$INPUT>) {
		tr/\015//d;

		# Sometimes "show diag" just ends while we are
		# trying to process this pcb stuff.  Check for a
		# prompt so we can get out.
		if (/^$prompt/) {
		    $found_diag = 1;
		    goto PerlSucks;
		}

		if (/0x..: / || /^$/) {
		    # no effing idea why break does not work there
		    goto PerlSucks;
		}
		if (/hardware revision\s+:\s+(\S+)/i) { $hw = $1; }
		if (/part number\s+:\s+(\S+)/i) { $pn = $1; }
		if (/board revision\s+:\s+(\S+)/i) { $rev = $1; }
		if (/pcb serial number\s+:\s+(\S+)/i) { $sn = $1; }
		# fru/pid bits, true Cisco evolving "standard", hopefully
		# "show inventory" will be "the way" soon.
		#
		if (/product \(fru\) number\s+:\s+(\S+)/i) { $fn = $1; }
		if (/product number\s+:\s+(\S+)/i) { $fn = $1; }
		if (/product\s+identifier\s+\(PID\)\s+:\s+(\S+)/i) { $fn = $1; }
		if (/fru\s+part\s+number\s+(\S+)/i) { $fn = $1; }
	    }
PerlSucks:
	    # fru/pid bits
	    # If slot is blank, call it "Chassis"
	    if ($slot eq "") {
		$slot = "Chassis";
	    }
	    ProcessHistory("SLOT","keysort","AG","!Slot $slot$WIC: fru $fn\n");
	    #
	    ProcessHistory("SLOT","keysort","B","!Slot $slot$WIC: hvers $hw rev $rev\n");
	    ProcessHistory("SLOT","keysort","C","!Slot $slot$WIC: part $pn, serial $sn\n");
	    # If we saw the prompt, then we are done.
	    last if $found_diag;
	}
	/revision\s+(\S+).*revision\s+(\S+)/ &&
	    ProcessHistory("SLOT","keysort","C","!Slot $slot$WIC: hvers $1 rev $2\n") &&
	    next;
	/number\s+(\S+)\s+Part number\s+(\S+)/ &&
	    ProcessHistory("SLOT","keysort","D","!Slot $slot$WIC: part $2, serial $1\n") &&
	    next;
	# AS5x00 bits
	/^\ Board Revision\s+(\S+),\s+Serial Number\s+(\S+),/ &&
	    ProcessHistory("SLOT","keysort","D",
			   "!Slot $slot$WIC: rev $1, serial $2\n") && next;
	/^\ Board Hardware Version\s+(\S+),\s+Item Number\s+(\S+),/ &&
	    ProcessHistory("SLOT","keysort","D",
			   "!Slot $slot$WIC: hvers $1, part $2\n") && next;
	/^Motherboard Info:/ &&
	    ProcessHistory("SLOT","keysort","D",
			   "!Slot $slot$WIC: Motherboard\n") && next;
	#
    }
    ProcessHistory("SLOT","","","!\n");
    return(0);
}

# This routine parses "show inventory".
sub ShowInventory {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowInventory: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	return if (/^\s*\^$/);
	if (/^$prompt/) { $found_inventory = 1; last};
	next if (/^(\s*|\s*$cmd\s*)$/);
	return(1) if (/Line has invalid autocommand /);
	next if (/^\s+\^\s*$/);
	next if (/^Load for five/);
	next if (/^Time source is/);
	return(1) if (/(invalid (input|command) detected|type help or )/i);
	return(-1) if (/(?:%|command)? authorization failed/i);
	return(0) if ($found_inventory);	# Only do this routine once
	# the pager can not be disabled per-session on the PIX
	if (/^(<-+ More -+>)/) {
	    my($len) = length($1);
	    s/^$1\s{$len}//;
	}

	next if (/^Load for /);
	next if (/^Time source is /);
	if (/^(NAME: "[^"]*",) (DESCR: "[^"]+")/) {
	    ProcessHistory("INVENTORY","","", sprintf("!%-30s %s\n", $1, $2));
	    next;
	}
	# split PID/VID/SN line
	if (/^PID: (\S*)\s*,\s*VID: (\S*)\s*,\s*SN: (\S*)\s*$/) {
	    my($pid,$vid,$sn) = ($1, $2, $3);
	    my($entries) = "";
	    # filter <empty>, "0x" and "N/A" lines
	    if ($pid !~ /^(|0x|N\/A)$/) {
		$entries .= "!PID: $pid\n";
	    }
	    if ($vid !~ /^(|0x|N\/A)$/) {
		$entries .= "!VID: $vid\n";
	    }
	    if ($sn !~ /^(|0x|N\/A)$/) {
		$entries .= "!SN: $sn\n";
	    }
	    ProcessHistory("INVENTORY","","", "$entries");
	    next;
	}
	ProcessHistory("INVENTORY","","","!$_");
    }
    ProcessHistory("INVENTORY","","","!\n");

    return(0);
}

# This routine parses "show module".
sub ShowModule {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowModule: $_" if ($debug);

    my(@lines);
    my($slot, $pa);
    my($switch, $switch_n);

    if ($vss_show_module == 1) {
	while (<$INPUT>) {
	    last if (/^$prompt/);
	}
	return(0);
    }
    while (<$INPUT>) {
	tr/\015//d;
	next if (/^\s*\^$/);
	next if (/^Load for five/);
	next if (/^Time source is/);
	if (/online diag status/i) {
	    $vss_show_module = 1;
	    next;
	}
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	return(-1) if (/(?:%|command)? authorization failed/i);
	# the pager can not be disabled per-session on the PIX
	if (/^(<-+ More -+>)/) {
	    my($len) = length($1);
	    s/^$1\s{$len}//;
	}

	# match  Switch Number:     2   Role:  Virtual Switch Active/Standby
	if (/^ *Switch Number: *(\d) .*Virtual Switch\s+(\S+)/) {
	    $switch_n = $1;
	    $switch = "Sw$1 ";
	    ProcessHistory("Module","","","!Virtual Switch $1 is $2\n");
	    next;
	}

	# match slot/card info line
	if (/^ *(\d+)\s+(\d+)\s+(.*)\s+(\S+)\s+(\S+)\s*$/) {
	    $lines[$switch_n * 10000 + $1 * 1000] .= "!Slot ${switch}$1: type $3, $2 ports\n!Slot ${switch}$1: part $4, serial $5\n";
	    $lines[$switch_n * 10000 + $1 * 1000] =~ s/\s+,/,/g;
	    next;
	}
	# now match the Revs in the second paragraph of o/p and stick it in
	# the array with the previous bits...grumble.
	if (/^ *(\d+)\s+\S+\s+to\s+\S+\s+(\S+)\s+(\S*)\s+(\S+)(\s+\S+)?\s*$/) {
	    $lines[$switch_n * 10000 + $1 * 1000] .= "!Slot ${switch}$1: hvers $2, firmware $3, sw $4\n";
	    $lines[$switch_n * 10000 + $1 * 1000] =~ s/\s+,/,/g;
	    next;
	}
	# grab the sub-modules, if any
	if (/^\s+(\d+)\s(.*)\s+(\S+)\s+(\S+)\s+(\S+)\s+\S+\s*$/) {
	    my($idx);
	    $pa = 0 if ($1 != $slot);
	    $slot = $1;
	    $idx = $switch_n * 10000 + $1 * 1000 + $1 * 10 + $pa;
	    $lines[$idx] .= "!Slot ${switch}$1/$pa: type $2\n";
	    $lines[$idx] .= "!Slot ${switch}$slot/$pa: part $3, serial $4\n";
	    $lines[$idx] .= "!Slot ${switch}$slot/$pa: hvers $5\n";
	    $pa++;
	}
    }
    if ($switch_n != 0) {
	ProcessHistory("Module","","","!\n");
    }
    foreach $slot (@lines) {
	next if ($slot =~ /^\s*$/);
	ProcessHistory("Module","","","$slot!\n");
    }

    return(0);
}

# This routine parses "show spe version".
sub ShowSpeVersion {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowSpeVersion: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	return(1) if /^\s*\^\s*$/;
	return(1) if (/Line has invalid autocommand /);
	next if (/^\s+\^\s*$/);
	next if (/^Load for five/);
	next if (/^Time source is/);
	return(1) if (/(invalid (input|command) detected|type help or )/i);
	return(-1) if (/(?:%|command)? authorization failed/i);

	ProcessHistory("MODEM","","","!Modem: $_") && next;
    }
    ProcessHistory("MODEM","","","!\n");
    return(0);
}

# This routine parses "show c7200" for the 7200
# This will create arrays for hw info.
sub ShowC7200 {
    my($INPUT, $OUTPUT, $cmd) = @_;
    # Skip if this is not a 7200.
    print STDERR "    In ShowC7200: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	next if (/^\s+\^\s*$/);
	next if (/^Load for five/);
	next if (/^Time source is/);
	return(1) if (/(invalid (input|command) detected|type help or )/i);
	#return(1) if ($type !~ /^72/);
	return(-1) if (/(?:%|command)? authorization failed/i);
	/^$/ && next;
	# the pager can not be disabled per-session on the PIX
	if (/^(<-+ More -+>)/) {
	    my($len) = length($1);
	    s/^$1\s{$len}//;
	}

	if (/^(C7200 )?Midplane EEPROM:/) {
	    $_ = <$INPUT>;
	    /revision\s+(\S+).*revision\s+(\S+)/;
	    ProcessHistory("SLOT","","","!Slot Midplane: hvers $1 rev $2\n");
	    $_ = <$INPUT>;
	    /number\s+(\S+)\s+Part number\s+(\S+)/;
	    ProcessHistory("SLOT","","","!Slot Midplane: part $2, serial $1\n!\n");
	    next;
	}
	if (/C720\d(VXR)? CPU EEPROM:/) {
	    my ($hvers,$rev,$part,$serial);
	    # npe400s report their cpu eeprom info differently w/ 12.0.21S
	    while (<$INPUT>) {
		/Hardware Revision\s+: (\S+)/ && ($hvers = $1) && next;
		/Board Revision\s+: (\S+)/ && ($rev = $1) && next;
		/Part Number\s+: (\S+)/ && ($part = $1) && next;
		/Serial Number\s+: (\S+)/ && ($serial = $1) && next;
		/revision\s+(\S+).*revision\s+(\S+)/ &&
		    ($hvers = $1, $rev = $2) && next;
		/number\s+(\S+)\s+Part number\s+(\S+)/ &&
		    ($serial = $1, $part = $2) && next;
		/^\s*$/ && last;
	    }
	    ProcessHistory("SLOT","","","!Slot CPU: hvers $hvers rev $rev\n");
	    ProcessHistory("SLOT","","","!Slot CPU: part $part, serial $serial\n!\n");
	    next;
	}
    }
    return(0);
}

# This routine parses "show capture".  Intended for ASA/PIXes.
sub ShowCapture {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowCapture: $_" if ($debug);
    my $capture_found = 0;
    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	return(1) if (/^(\s*|\s*$cmd\s*)$/);
	return(1) if /^\s*\^\s*$/;
	return(1) if (/Line has invalid autocommand /);
	next if (/^\s+\^\s*$/);
	next if (/^Load for five/);
	next if (/^Time source is/);
	return(1) if (/(invalid (input|command) detected|type help or )/i);
	return(-1) if (/(?:%|command)? authorization failed/i);
	# the pager can not be disabled per-session on the PIX
	if (/^(<-+ More -+>)/) {
	    my($len) = length($1);
	    s/^$1\s{$len}//;
	}

	if (/capture (.*) type/) {
	    my $cap_name = $1;
	    s/\d+ bytes/<COUNTER> bytes/;
	    ProcessHistory("CAPTURE","","","!Capture: $cap_name\n");
	    ProcessHistory("CAPTURE","","","!Capture: $_");
	} else {
	    ProcessHistory("CAPTURE","","","!Capture: $_");
	}
        $capture_found = 1
    }
    ProcessHistory("CAPTURE","","","!\n") if ($capture_found == 1);
    return(0);
}

# This routine parses "show dot1x"
sub ShowDot1x {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowVTP: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	return(1) if /^\s*\^\s*$/;
	return(1) if (/Line has invalid autocommand /);
	next if (/^\s+\^\s*$/);
	next if (/^Load for five/);
        next if (/^Time source is/);
	return(1) if (/(invalid (input|command) detected|type help or )/i);
	return(-1) if (/(?:%|command)? authorization failed/i);
	next if (/^Configuration last modified by/);
	# the pager can not be disabled per-session on the PIX
	if (/^(<-+ More -+>)/) {
	    my($len) = length($1);
	    s/^$1\s{$len}//;
	}

	# if dot1x is enabled, do not collect show vlan output
	if (/^sysauthcontrol\s+(?:=\s+)?(\S+)/i) {
	    if ($1 !~ /disabled/i && $filter_osc > 1) {
		$DO_SHOW_VLAN = 1;
	    }
	}
	ProcessHistory("COMMENTS","keysort","I0","!DOT1x: $_");
    }
    ProcessHistory("COMMENTS","keysort","I0","!\n");
    return(0);
}


# This routine parses "show vtp status"
sub ShowVTP {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowVTP: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	return(1) if /^\s*\^\s*$/;
	return(1) if (/Line has invalid autocommand /);
	next if (/^\s+\^\s*$/);
	next if (/^Load for five/);
	next if (/^Time source is/);
	return(1) if (/(invalid (input|command) detected|type help or )/i);
	#return(1) if ($type !~ /^(2900XL|3500XL|6000)$/);
	return(-1) if (/(?:%|command)? authorization failed/i);
	next if (/^Configuration last modified by/);
	# the pager can not be disabled per-session on the PIX
	if (/^(<-+ More -+>)/) {
	    my($len) = length($1);
	    s/^$1\s{$len}//;
	}

	if (/^VTP Operating Mode\s+:\s+(Client)/) {
	    $DO_SHOW_VLAN = 1;
	}
	ProcessHistory("COMMENTS","keysort","I0","!VTP: $_");
    }
    ProcessHistory("COMMENTS","keysort","I0","!\n");
    return(0);
}

# This routine parses "show vlan"
sub ShowVLAN {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowVLAN: $_" if ($debug);

    ($_ = <$INPUT>, return(1)) if ($DO_SHOW_VLAN);

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	return(1) if /^\s*\^\s*$/;
	return(1) if (/Line has invalid autocommand /);
	next if (/^\s+\^\s*$/);
	next if (/^Load for five/);
	next if (/^Time source is/);
	return(1) if (/(invalid (input|command) detected|type help or )/i);
	return(1) if (/ambiguous command/i);
	return(1) if (/incomplete command/i);
	return(-1) if (/(?:%|command)? authorization failed/i);
	# the pager can not be disabled per-session on the PIX
	if (/^(<-+ More -+>)/) {
	    my($len) = length($1);
	    s/^$1\s{$len}//;
	}
	return(0) if (/no virtual lans configured/i);
	# some ASAs do not support show vlan
	return(0) if (/use .show switch vlan. to view the vlans that have /i);

	# GSR-specific, i think, filter
	if (/received:\s+transmitted:/i) {
	    while (<$INPUT>) {
		last if (/^\s*$/);
		goto OUT if (/^$prompt/);
	    }
	}

	next if (/total.*packets.*(input|output)/i);

	# Aironet AP's traffic counters
	next if (/\d+\s+bytes.*(input|output)/i);
	next if (/^\s*Other\s+\d+\s+\d+\s*$/i);
	next if (/^\s*Bridging\s+Bridge.Group.\d+\s+\d+\s+\d+\s*$/i);

	ProcessHistory("COMMENTS","keysort","IO","!VLAN: $_");
    }
OUT:ProcessHistory("COMMENTS","keysort","IO","!\n");
    return(0);
}

# This routine processes a "show shun".  Intended for ASA/PIXes.
sub ShowShun {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowShun: $_" if ($debug);
    my $shun_found = 0;

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	return(1) if (/^(\s*|\s*$cmd\s*)$/);
	return(1) if /^\s*\^\s*$/;
	return(1) if (/Line has invalid autocommand /);
	return(1) if (/(invalid (input|command) detected|type help or )/i);
	return(-1) if (/(?:%|command)? authorization failed/i);

	next if (/^\s+\^\s*$/);
	next if (/^Load for five/);
	next if (/^Time source is/);
	# the pager can not be disabled per-session on the PIX
	if (/^(<-+ More -+>)/) {
	    my($len) = length($1);
	    s/^$1\s{$len}//;
	}

	ProcessHistory("SHUN","","","!Shun: $_");
	$shun_found = 1;
    }
    ProcessHistory("SHUN","","","!\n") if ($shun_found == 1);
    return(0);
}

# This routine processes a "write term"
sub WriteTerm {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In WriteTerm: $_" if ($debug);
    my($comment, $linecnt) = (0,0);

    while (<$INPUT>) {
TOP:
	tr/\015//d;
	last if (/^$prompt/);
	return(1) if (!$linecnt && /^\s+\^\s*$/);
	next if (/^\s*$cmd\s*$/);
	return(1) if (/Line has invalid autocommand /);
	next if (/^\s+\^\s*$/);
	next if (/^Load for five/);
	next if (/^Time source is/);
	return(1) if (/(invalid (input|command) detected|type help or )/i);
	return(1) if (/\%Error: No such file or directory/);
	return(1) if (/(Open device \S+ failed|Error opening \S+:)/);
	return(0) if ($found_end);		# Only do this routine once
	return(-1) if (/(?:%|command)? authorization failed/i);
	return(-1) if (/% ?configuration buffer full/i);
	# the pager can not be disabled per-session on the PIX
	if (/^(<-+ More -+>)/) {
	    my($len) = length($1);
	    s/^$1\s{$len}//;
	}
	/^! no configuration change since last restart/i && next;
	# skip emtpy lines at the beginning
	if (!$linecnt && /^\s*$/) {
	    next;
	}
	if (!$linecnt && defined($config_register)) {
	    ProcessHistory("","","", "!\nconfig-register $config_register\n");
	}

	/Non-Volatile memory is in use/ && return(-1); # NvRAM is locked
	/% Configuration buffer full, / && return(-1); # buffer is in use
	$linecnt++;
	# skip the crap
	if (/^(##+|(building|current) configuration)/i) {
	    while (<$INPUT>) {
		next if (/^Current configuration\s*:/i);
		next if (/^:/);
		next if (/^([%!].*|\s*)$/);
		next if (/^ip add.*ipv4:/);	# band-aid for 3620 12.0S
		last;
	    }
	    tr/\015//d;
	}
	# config timestamp on MDS/NX-OS
	/Time: / && next;
	# skip ASA 5520 configuration author line
	/^: written by /i && next;
	# some versions have other crap mixed in with the bits in the
	# block above
	/^! (Last configuration|NVRAM config last)/ && next;
	# and for the ASA
	/^: (Written by \S+ at|Saved)/ && next;

	# skip consecutive comment lines to avoid oscillating extra comment
	# line on some access servers.  grrr.
	if (/^!\s*$/) {
	    next if ($comment);
	    ProcessHistory("","","",$_);
	    $comment++;
	    next;
	}
	$comment = 0;

	# Dog gone Cool matches to process the rest of the config
	/^tftp-server flash /   && next; # kill any tftp remains
	/^ntp clock-period /    && next; # kill ntp clock-period
	/^ clockrate /		&& next; # kill clockrate on serial interfaces
	# kill rx/txspeed (particularly on cellular modem cards)
	if (/^(line (\d+(\/\d+\/\d+)?|con|aux|vty))/) {
	    my($key) = $1;
	    my($lineauto) = (0);
	    if ($key =~ /con/) {
		$key = -1;
	    } elsif ($key =~ /aux/) {
		$key = -2;
	    } elsif ($key =~ /vty/) {
		$key = -3;
	    }
	    ProcessHistory("LINE","keysort","$key","$_");
	    while (<$INPUT>) {
		tr/\015//d;
		last if (/^$prompt/);
		goto TOP if (! /^ /);
		next if (/\s*(rx|tx)speed \d+/);
		next if (/^ length /);	# kill length on serial lines
		next if (/^ width /);	# kill width on serial lines
		$lineauto = 0 if (/^[^ ]/);
		$lineauto = 1 if /^ modem auto/;
		/^ speed / && $lineauto	&& next; # kill speed on serial lines
		if (/^(\s+password) \d+ / && $filter_pwds >= 1) {
		    $_ = "!$1 <removed>\n";
		}
		ProcessHistory("LINE","keysort","$key","$_");
	    }
	}
	if (/^(enable )?(password|passwd)( level \d+)? / && $filter_pwds >= 1) {
	    ProcessHistory("ENABLE","","","!$1$2$3 <removed>\n");
	    next;
	}
	if (/^(enable secret) / && $filter_pwds >= 2) {
	    ProcessHistory("ENABLE","","","!$1 <removed>\n");
	    next;
	}
	if (/^username (\S+)(\s.*)? secret /) {
	    if ($filter_pwds >= 2) {
		ProcessHistory("USER","keysort","$1",
			       "!username $1$2 secret <removed>\n");
	    } else {
		ProcessHistory("USER","keysort","$1","$_");
	    }
	    next;
	}
	if (/^username (\S+)(\s.*)? password ((\d) \S+|\S+)/) {
	    if ($filter_pwds >= 2) {
		ProcessHistory("USER","keysort","$1",
			       "!username $1$2 password <removed>\n");
	    } elsif ($filter_pwds >= 1 && $4 ne "5"){
		ProcessHistory("USER","keysort","$1",
			       "!username $1$2 password <removed>\n");
	    } else {
		ProcessHistory("USER","keysort","$1","$_");
	    }
	    next;
	}
	# cisco AP w/ IOS
	if (/^(wlccp \S+ username (\S+)(\s.*)? password) (\d \S+|\S+)/) {
	    if ($filter_pwds >= 1) {
		ProcessHistory("USER","keysort","$2","!$1 <removed>\n");
	    } else {
		ProcessHistory("USER","keysort","$2","$_");
	    }
	    next;
	}
	# filter auto "rogue ap" configuration lines
	/^rogue ap classify / && next;
	if (/^( set session-key (in|out)bound ah \d+ )/ && $filter_pwds >= 1) {
	    ProcessHistory("","","","!$1<removed>\n");
	    next;
	}
	if (/^( set session-key (in|out)bound esp \d+ (authenticator|cypher) )/
	    && $filter_pwds >= 1) {
	    ProcessHistory("","","","!$1<removed>\n");
	    next;
	}
	if (/^(\s*)password / && $filter_pwds >= 1) {
	    ProcessHistory("LINE-PASS","","","!$1password <removed>\n");
	    next;
	}
	if (/^(\s*)secret / && $filter_pwds >= 2) {
	    ProcessHistory("LINE-PASS","","","!$1secret <removed>\n");
	    next;
	}
	if (/^\s*(.*?neighbor.*?) (\S*) password / && $filter_pwds >= 1) {
	    ProcessHistory("","","","! $1 $2 password <removed>\n");
	    next;
	}
	if (/^(\s*ppp .* hostname) .*/ && $filter_pwds >= 1) {
	    ProcessHistory("","","","!$1 <removed>\n"); next;
	}
	if (/^(\s*ppp .* password) \d .*/ && $filter_pwds >= 1) {
	    ProcessHistory("","","","!$1 <removed>\n"); next;
	}
	if (/^(ip ftp password) / && $filter_pwds >= 1) {
	    ProcessHistory("","","","!$1 <removed>\n"); next;
	}
	if (/^( ip ospf authentication-key) / && $filter_pwds >= 1) {
	    ProcessHistory("","","","!$1 <removed>\n"); next;
	}
	# isis passwords appear to be completely plain-text
	if (/^\s+isis password (\S+)( .*)?/ && $filter_pwds >= 1) {
	    ProcessHistory("","","","!isis password <removed>$2\n"); next;
	}
	if (/^\s+(domain-password|area-password) (\S+)( .*)?/
							&& $filter_pwds >= 1) {
	    ProcessHistory("","","","!$1 <removed>$3\n"); next;
	}
	# this is reversable, despite 'md5' in the cmd
	if (/^( ip ospf message-digest-key \d+ md5) / && $filter_pwds >= 1) {
	    ProcessHistory("","","","!$1 <removed>\n"); next;
	}
	# this is also reversable, despite 'md5 encrypted' in the cmd
	if (/^(  message-digest-key \d+ md5 (7|encrypted)) /
	    && $filter_pwds >= 1) {
	    ProcessHistory("","","","!$1 <removed>\n"); next;
	}
	if (/^((crypto )?isakmp key) (\d )?\S+ / && $filter_pwds >= 1) {
	    ProcessHistory("","","","!$1 <removed> $'"); next;
	}
	# filter HSRP passwords
	if (/^(\s+standby \d+ authentication) / && $filter_pwds >= 1) {
	    ProcessHistory("","","","!$1 <removed>\n"); next;
	}
	# this appears in "measurement/sla" images
	if (/^(\s+key-string \d?)/ && $filter_pwds >= 1) {
	    ProcessHistory("","","","!$1 <removed>\n"); next;
	}
	if (/^( l2tp tunnel \S+ password)/ && $filter_pwds >= 1) {
	    ProcessHistory("","","","!$1 <removed>\n"); next;
	}
	# l2tp-class secret
	if (/^( digest secret 7?)/ && $filter_pwds >= 1) {
	    ProcessHistory("","","","!$1 <removed>\n"); next;
	}
	# i am told these are plain-text on the PIX
	if (/^(vpdn username (\S+) password)/) {
	    if ($filter_pwds >= 1) {
		ProcessHistory("USER","keysort","$2","!$1 <removed>\n");
	    } else {
		ProcessHistory("USER","keysort","$2","$_");
	    }
	    next;
	}
	# ASA/PIX keys in more system:running-config
	if (/^(( ikev2)? (local|remote)-authentication pre-shared-key ).*/ &&
	    $filter_pwds >= 1) {
	    ProcessHistory("","","","!$1 <removed> $'"); next;
	}
	# ASA/PIX keys in more system:running-config
	if (/^(( ikev1)? pre-shared-key | key |failover key ).*/ &&
	    $filter_pwds >= 1) {
	    ProcessHistory("","","","!$1 <removed> $'"); next;
	}
	# ASA/PIX keys in more system:running-config
	if (/(\s+ldap-login-password )\S+(.*)/ && $filter_pwds >= 1) {
	    ProcessHistory("","","","!$1 <removed> $'"); next;
	}
	# filter WPA password such as on cisco 877W ISR
	if (/^\s+(wpa-psk ascii|hex \d) / && $filter_pwds >= 1) {
	    ProcessHistory("","","","!$1 <removed>\n"); next;
	}
	#
	if (/^( cable shared-secret )/ && $filter_pwds >= 1) {
	    ProcessHistory("","","","!$1 <removed>\n");
	    next;
	}
	/fair-queue individual-limit/ && next;
	# sort ip explicit-paths.
	if (/^ip explicit-path name (\S+)/) {
	    my($key) = $1;
	    my($expath) = $_;
	    while (<$INPUT>) {
		tr/\015//d;
		last if (/^$prompt/ || ! /^(ip explicit-path name |[ !])/);
		if (/^ip explicit-path name (\S+)/) {
		    ProcessHistory("EXPATH","keysort","$key","$expath");
		    $key = $1;
		    $expath = $_;
		} else  {
		    $expath .= $_;
		}
	    }
	    ProcessHistory("EXPATH","keysort","$key","$expath");
	}
	# sort route-maps
	if (/^route-map (\S+)/) {
	    my($key) = $1;
	    my($routemap) = $_;
	    while (<$INPUT>) {
		tr/\015//d;
		last if (/^$prompt/ || ! /^(route-map |[ !])/);
		if (/^route-map (\S+)/) {
		    ProcessHistory("ROUTEMAP","keysort","$key","$routemap");
		    $key = $1;
		    $routemap = $_;
		} else  {
		    $routemap .= $_;
		}
	    }
	    ProcessHistory("ROUTEMAP","keysort","$key","$routemap");
	}
	# filter out any RCS/CVS tags to avoid confusing local CVS storage
	s/\$(Revision|Id):/ $1:/;
	# order access-lists
	/^access-list\s+(\d\d?)\s+(\S+)\s+(\S+)/ &&
	    ProcessHistory("ACL $1 $2","$aclsort","$3","$_") && next;
	# order extended access-lists
	if ($aclfilterseq) {
	/^access-list\s+(\d\d\d)\s+(\S+)\s+(\S+)\s+host\s+(\S+)/ &&
	    ProcessHistory("EACL $1 $2","$aclsort","$4","$_") && next;
	/^access-list\s+(\d\d\d)\s+(\S+)\s+(\S+)\s+(\d\S+)/ &&
	    ProcessHistory("EACL $1 $2","$aclsort","$4","$_") && next;
	/^access-list\s+(\d\d\d)\s+(\S+)\s+(\S+)\s+any/ &&
	    ProcessHistory("EACL $1 $2","$aclsort","0.0.0.0","$_") && next;
	}
	if ($aclfilterseq) {
	    /^ip(v6)? prefix-list\s+(\S+)\s+seq\s+(\d+)\s+(permit|deny)\s+(\S+)(.*)/
		&& ProcessHistory("PACL $2 $4","$aclsort","$5",
				  "ip$1 prefix-list $2 $4 $5$6\n")
		&& next;
	}
	# sort ipv{4,6} access-lists
	if ($aclfilterseq && /^ipv(4|6) access-list (\S+)\s*$/) {
	    my($nlri, $key) = ($1, $2);
	    my($seq, $cmd);
	    ProcessHistory("ACL $nlri $key","","","$_");
	    while (<$INPUT>) {
		tr/\015//d;
		last if (/^$prompt/ || /^\S/);
		# ipv4 access-list name
		#  remark NTP
   		#  deny ipv4 host 224.0.1.1 any
		#  deny ipv4 239.0.0.0 0.255.255.255 any
		#  permit udp any eq 123 any
		#  permit ipv4 nnn.nnn.nnn.nnn/nn any
		#  permit nnn.nnn.nnn.nnn/nn
		# ipv6 access-list name
		#  permit ipv6 host 2001:nnnn::nnnn any
		#  permit ipv6 2001:nnn::/nnn any
		#  permit 2001:nnnn::/64 any
		#  permit udp any eq 123 any
		#
		# line might begin with " sequence nnn permit ..."
		s/^\s+(sequence (\d+)) / /;
		my($seq) = $1;
		my($cmd, $resid) = ($_ =~ /^\s+(\w+) (.+)/);
		if ($cmd =~ /(permit|deny)/) {
		    my($ip);
		    my(@w) = ($resid =~ /(\S+) (\S+) (\S+\s)?(.+)/);
		    for (my($i) = 0; $i < $#w; $i++) {
			if ($w[$i] eq "any") {
			    if ($nlri eq "ipv4") {
				$ip = "255.255.255.255/32";
			    } else {
				$ip = "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff/128";
			    }
			    last;
			} elsif ($w[$i] =~ /^[:0-9]/ ||
				 $2[$i] =~ /^[a-fA-F]{1,4}:/) {
			    $ip = $w[$i];
			    $ip =~ s/\s+$//;		# trim trailing WS
			    last;
			}
		    }
		    ProcessHistory("ACL $nlri $key $cmd", "$aclsort", "$ip",
				   " $cmd $resid\n");
		} else {
		    ProcessHistory("ACL $nlri $key $cmd", "", "",
				   " $cmd $resid\n");
		}
	    }
	}
	# order arp lists
	/^arp\s+(\d+\.\d+\.\d+\.\d+)\s+/ &&
	    ProcessHistory("ARP","$aclsort","$1","$_") && next;
	# order logging statements
	/^logging (\d+\.\d+\.\d+\.\d+)/ &&
	    ProcessHistory("LOGGING","ipsort","$1","$_") && next;
	# order/prune snmp-server host statements
	# we only prune lines of the form
	# snmp-server host a.b.c.d <community>
	if (/^snmp-server host (\d+\.\d+\.\d+\.\d+) /) {
	    if ($filter_commstr) {
		my($ip) = $1;
		my($line) = "snmp-server host $ip";
		my(@tokens) = split(' ', $');
		my($token);
		while ($token = shift(@tokens)) {
		    if ($token eq 'version') {
			$line .= " " . join(' ', ($token, shift(@tokens)));
			if ($token eq '3') {
			    $line .= " " . join(' ', ($token, shift(@tokens)));
			}
		    } elsif ($token eq 'vrf') {
			$line .= " " . join(' ', ($token, shift(@tokens)));
		    } elsif ($token =~ /^(informs?|traps?|(no)?auth)$/) {
			$line .= " " . $token;
		    } else {
			$line = "!$line " . join(' ', ("<removed>",
						 join(' ',@tokens)));
			last;
		    }
		}
		ProcessHistory("SNMPSERVERHOST","ipsort","$ip","$line\n");
	    } else {
		ProcessHistory("SNMPSERVERHOST","ipsort","$1","$_");
	    }
	    next;
	}
	# For ASA version 8.x and higher, the format changed a little. It is
	# 'snmp-server host {interface {hostname | ip_address}} [trap | poll]
	# [community  0 | 8 community-string] [version {1 | 2c | 3 username}]
	# [udp-port port] '
	if (/^(snmp-server .*community) ([08] )?(\S+)/) {
	    if ($filter_commstr) {
		ProcessHistory("SNMPSERVERCOMM","keysort","$_",
			       "!$1 <removed>$'") && next;
	    } else {
		ProcessHistory("SNMPSERVERCOMM","keysort","$_","$_") && next;
	    }
	}
	# prune tacacs/radius server keys
	if (/^((tacacs|radius)-server\s(\w*[-\s(\s\S+])*\s?key) (\d )?\S+/
	    && $filter_pwds >= 1) {
	    ProcessHistory("","","","!$1 <removed>$'"); next;
	}
	# order clns host statements
	/^clns host \S+ (\S+)/ &&
	    ProcessHistory("CLNS","keysort","$1","$_") && next;
	# order alias statements
	/^alias / && ProcessHistory("ALIAS","keysort","$_","$_") && next;
	# delete ntp auth password - this md5 is a reversable too
	if (/^(ntp authentication-key \d+ md5) / && $filter_pwds >= 1) {
	    ProcessHistory("","","","!$1 <removed>\n"); next;
	}
	# order ntp peers/servers
	if (/^ntp (server|peer) (\d+)\.(\d+)\.(\d+)\.(\d+)/) {
	    my($sortkey) = sprintf("$1 %03d%03d%03d%03d",$2,$3,$4,$5);
	    ProcessHistory("NTP","keysort",$sortkey,"$_");
	    next;
	}
	# order ip host statements
	/^ip host (\S+) / &&
	    ProcessHistory("IPHOST","keysort","$1","$_") && next;
	# order ip nat source static statements
	/^ip nat (\S+) source static (\S+)/ &&
	    ProcessHistory("IP NAT $1","ipsort","$2","$_") && next;
	# order atm map-list statements
	/^\s+ip\s+(\d+\.\d+\.\d+\.\d+)\s+atm-vc/ &&
	    ProcessHistory("ATM map-list","ipsort","$1","$_") && next;
	# order ip rcmd lines
	/^ip rcmd/ && ProcessHistory("RCMD","keysort","$_","$_") && next;

	# system controller
	/^syscon address (\S*) (\S*)/ &&
	    ProcessHistory("","","","!syscon address $1 <removed>\n") &&
	    next;
	if (/^syscon password (\S*)/ && $filter_pwds >= 1) {
	    ProcessHistory("","","","!syscon password <removed>\n");
	    next;
	}

	/^ *Cryptochecksum:/ && next;

	# catch anything that wasnt matched above.
	ProcessHistory("","","","$_");
	# end of config.  the ": " game is for the PIX
	if (/^(: +)?end$/) {
	    $found_end = 1;
	    return(0);
	}
    }
    # The ContentEngine lacks a definitive "end of config" marker.  If we
    # know that it is a CE, SAN, or NXOS and we have seen at least 5 lines
    # of write term output, we can be reasonably sure that we have the config.
    if (($type eq "CE" || $type eq "SAN" || $type eq "NXOS") && $linecnt > 5) {
	$found_end = 1;
	return(0);
    }

    return(0);
}

1;
