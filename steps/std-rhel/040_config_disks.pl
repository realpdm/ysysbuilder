######################################################################
# Copyright (c) 2012, Yahoo! Inc. All rights reserved.
#
# This program is free software. You may copy or redistribute it under
# the same terms as Perl itself. Please see the LICENSE.Artistic file 
# included with this project for the terms of the Artistic License
# under which this project is licensed. 
######################################################################

#!/usr/bin/perl

use strict;
use warnings 'all';
use YAML qw();
use lib '/sysbuilder/lib';
use SysBuilder::DiskConfig;

my $cfg = YAML::LoadFile('/sysbuilder/etc/config.yaml');
my $disks = SysBuilder::DiskConfig->new( cfg => $cfg );

$disks->setup( only_reconfigure => $cfg->{only_reconfigure} );
exit 0;
