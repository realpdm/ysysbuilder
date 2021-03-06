#!/usr/local/bin/perl

use strict;
use warnings 'all';

use FindBin(qw($Bin));
use lib qq($Bin/../lib);

use Test::More tests => 14;
use Test::Differences;
use SysBuilder::Utils qw(read_file write_file);

my $module = 'SysBuilder::SystemFiles';

use_ok($module);
can_ok( $module, 'new' );
can_ok( $module, 'config' );

my @args;
my $exit_code;
my $fatal_error = 0;

undef *SysBuilder::SystemFiles::run_local;
undef *SysBuilder::SystemFiles::fatal_error;
*SysBuilder::SystemFiles::run_local = sub {
    push @args, $_[0];
    $exit_code;
};
*SysBuilder::SystemFiles::fatal_error = sub {
    $fatal_error = 1;
};

# test configure_ntp_conf
my $s_ntp = SysBuilder::SystemFiles->new(
    net => SysBuilder::Network->new(
        dhclient_file => "files/network-dhclient.yaml",
        dryrun        => 1,
    ),
    cfg => {},
);

$s_ntp->configure_ntp_conf( file => "/tmp/n.$$", dhclient_file => "files/network-dhclient.yaml" );
my $expected_ntp_conf = <<EOT;
# Generated by sysbuilder

driftfile /var/lib/ntp/drift
pidfile /var/run/ntpd.pid

server 169.254.100.10
server 169.254.100.11

restrict default ignore
restrict 127.0.0.1
restrict 169.254.100.10
restrict 169.254.100.11

EOT

my $ntp_conf = read_file("/tmp/n.$$");
eq_or_diff( $ntp_conf, $expected_ntp_conf, "ntp.conf generated from dhclient.yaml" );

# test configure_syslog_conf
my $s_syslog = SysBuilder::SystemFiles->new(
    net => SysBuilder::Network->new(
        dhclient_file => "files/network-dhclient.yaml",
        dryrun        => 1,
    ),
    cfg => {
        syslog_server => "syslog.net.foo.com",
    },
);

write_file( "/tmp/s.$$", "# syslog.conf test base\n" );
$s_syslog->configure_syslog_conf( file => "/tmp/s.$$" );
my $expected_syslog_conf = <<'EOT';
# syslog.conf test base
*.*       @syslog.net.foo.com
EOT

my $syslog_conf = read_file("/tmp/s.$$");
eq_or_diff( $syslog_conf, $expected_syslog_conf, "syslog.conf generated from cfg" );

# test configure_resolv_conf
my $s_resolv = SysBuilder::SystemFiles->new(
    net => undef,
    cfg => { dns => { search => 'test.foo.com', nameserver => [qw/1.2.3.4 1.2.3.5/] } }
);
$s_resolv->configure_resolv_conf( file => "/tmp/r.$$" );
my $resolv_conf = read_file("/tmp/r.$$");
unlink "/tmp/r.$$";

my $expected_resolv_conf = <<EOT;
; generated by sysbuilder
search test.foo.com

options attempts:3
options timeout:1

nameserver 1.2.3.4
nameserver 1.2.3.5

EOT
eq_or_diff( $resolv_conf, $expected_resolv_conf, "resolv.conf generated from cfg" );

$expected_resolv_conf = read_file("/etc/resolv.conf");
$s_resolv             = SysBuilder::SystemFiles->new(
    net => undef,
    cfg => {}
);
$s_resolv->configure_resolv_conf( file => "/tmp/r.$$" );
$resolv_conf = read_file("/tmp/r.$$");
unlink "/tmp/r.$$";
eq_or_diff( $resolv_conf, $expected_resolv_conf,
    "resolv.conf generated from system /etc/resolv.conf" );

my $cfg = { ip => '1.2.3.4', hostname => 'a_random_hostname', services => { 'kudzu' => 0, 'ntpd' => 1, 'xxx' => 0 } };

my $s1 = SysBuilder::SystemFiles->new( cfg => $cfg, net => undef );
unlink "/tmp/p.$$";
$s1->add_postinstall_steps( file => "/tmp/p.$$" );
ok( !-e "/tmp/p.$$", "postinstall script not generated unless present in config" );
$cfg->{postinstall} = [('first_step ::HOSTNAME::', 'second_step')];

my $s2 = SysBuilder::SystemFiles->new( cfg => $cfg, net => undef );
$s1->add_postinstall_steps( file => "/tmp/p.$$" );
ok( -e "/tmp/p.$$", "postinstall script generated" );
my $postinstall_sh = read_file("/tmp/p.$$");
unlink "/tmp/p.$$";

my $expected_postinstall = <<EOT;
#!/bin/sh

PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin

cd /

first_step a_random_hostname
second_step

EOT
eq_or_diff( $postinstall_sh, $expected_postinstall,
    "postinstall script generated correctly" );

my $sys = SysBuilder::SystemFiles->new( cfg => $cfg, net => undef );

undef *SysBuilder::SystemFiles::backtick;
*SysBuilder::SystemFiles::backtick = sub {
    my $services = <<EOT;
kudzu          0:off    1:off    2:on    3:on    4:on    5:on    6:off
ntpd           0:off    1:off    2:on    3:on    4:on    5:on    6:off
sshd           0:off    1:off    2:on    3:on    4:on    5:on    6:off
EOT
    return split '\n', $services;
};

$sys->configure_services;
eq_or_diff(
    \@args,
    [ 'chroot /mnt /sbin/chkconfig kudzu off', 'chroot /mnt /sbin/chkconfig ntpd on' ],
    "services configured"
);

eq_or_diff( $sys->esx("2.4.21-47.0.1.ELvmnix"),
    "2.4.21-47.0.1.ELvmnix", "esx recognized" );

delete $sys->{_esx};
eq_or_diff( $sys->esx("2.4.21-47.0.1.ELsmp"), 0, "not esx recognized" );

undef *SysBuilder::SystemFiles::backtick;
*SysBuilder::SystemFiles::backtick = sub {
    my $ifcfg = <<EOT;
eth0      Link encap:Ethernet  HWaddr 00:15:17:40:92:38
eth1      Link encap:Ethernet  HWaddr 00:15:17:40:92:39
EOT
    return split '\n', $ifcfg;
};

undef *SysBuilder::SystemFiles::_udev_version;
*SysBuilder::SystemFiles::_udev_version = sub {
    return "095";
};

my $expected = <<EOT;
# Generated By SysBuilder to prevent unwanted interface renaming
KERNEL=="eth*", SUBSYSTEM=="net", DRIVER=="?*", SYSFS{address}=="00:15:17:40:92:38", NAME="eth0"
KERNEL=="eth*", SUBSYSTEM=="net", DRIVER=="?*", SYSFS{address}=="00:15:17:40:92:39", NAME="eth1"
EOT

eq_or_diff( SysBuilder::SystemFiles::_generate_eth_rules(),
    $expected, 'eth.rules file generated correctly' );
