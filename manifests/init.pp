# == Class: haproxy
#
# A Puppet module, using storeconfigs, to model an haproxy configuration.
# Currently VERY limited - assumes Redhat/CentOS setup. Pull requests accepted!
#
# === Requirement/Dependencies:
#
# Currently requires the ripienaar/concat module on the Puppet Forge and
#  uses storeconfigs on the Puppet Master to export/collect resources
#  from all balancer members.
#
# === Parameters
#
# [*enable*]
#   Chooses whether haproxy should be installed or ensured absent.
#    Currently ONLY accepts valid boolean true/false values.
#
# [*global_options*]
#   A hash of all the haproxy global options. If you want to specify more
#    than one option (i.e. multiple timeout or stats options), pass those
#    options as an array and you will get a line for each of them in the
#    resultant haproxy.cfg file.
#
# [*defaults_options*]
#   A hash of all the haproxy defaults options. If you want to specify more
#    than one option (i.e. multiple timeout or stats options), pass those
#    options as an array and you will get a line for each of them in the
#    resultant haproxy.cfg file.
#
# [*package_name*]
#   The package name to install containing haproxy.  Defaults to <code>'haproxy'</code>
#
#[*restart_command*]
#   Command to use when restarting the on config changes.
#    Passed directly as the <code>'restart'</code> parameter to the service resource.
#    Defaults to undef i.e. whatever the service default is.
#
# === Examples
#
#  class { 'haproxy':
#    enable           => true,
#    global_options   => {
#      'log'     => "${::ipaddress} local0",
#      'chroot'  => '/var/lib/haproxy',
#      'pidfile' => '/var/run/haproxy.pid',
#      'maxconn' => '4000',
#      'user'    => 'haproxy',
#      'group'   => 'haproxy',
#      'daemon'  => '',
#      'stats'   => 'socket /var/lib/haproxy/stats'
#    },
#    defaults_options => {
#      'log'     => 'global',
#      'stats'   => 'enable',
#      'option'  => 'redispatch',
#      'retries' => '3',
#      'timeout' => [
#        'http-request 10s',
#        'queue 1m',
#        'connect 10s',
#        'client 1m',
#        'server 1m',
#        'check 10s'
#      ],
#      'maxconn' => '8000'
#    },
#  }
#
class haproxy (
  $manage_service   = true,
  $enable           = true,
  $global_options   = $haproxy::params::global_options,
  $defaults_options = $haproxy::params::defaults_options,
  $package_name     = 'haproxy',
  $restart_command  = undef,
  $custom_source_location = '',
  $custom_source_release  = '',
  $custom_source_repo     = '',
  $custom_source_is_backport = false
) inherits haproxy::params {
  include concat::setup

  if ($customer_source_location == '') {
    package { $package_name:
      ensure  => $enable ? {
        true  => present,
        false => absent,
      },
      alias   => 'haproxy',
    }
  else {
    include apt

    apt::source { 'haproxy':
      location => $custom_source_location,
      release => $custom_source_release,
      repos => $custom_source_repo,
      include_src => false
    }a

    package { $package_name:
      ensure  => $enable ? {
        true  => present,
        false => absent,
      },
      install_options => $custom_source_is_backport ? {
        true => ["-t"],
        false => []
      },
      alias   => 'haproxy'
    }
  }

  if $enable {
    concat { '/etc/haproxy/haproxy.cfg':
      owner   => '0',
      group   => '0',
      mode    => '0644',
      require => Package['haproxy'],
      notify  => $manage_service ? {
        true  => Service['haproxy'],
        false => undef,
      },
    }

    # Simple Header
    concat::fragment { '00-header':
      target  => '/etc/haproxy/haproxy.cfg',
      order   => '01',
      content => "# This file managed by Puppet\n",
    }

    # Template uses $global_options, $defaults_options
    concat::fragment { 'haproxy-base':
      target  => '/etc/haproxy/haproxy.cfg',
      order   => '10',
      content => template('haproxy/haproxy-base.cfg.erb'),
    }

    if ($::osfamily == 'Debian') {
      file { '/etc/default/haproxy':
        content => 'ENABLED=1',
        require => Package['haproxy'],
        before  => $manage_service ? {
          true  => Service['haproxy'],
          false => undef,
        },
      }
    }

    if $global_options['chroot'] {
      file { $global_options['chroot']:
        ensure => directory,
      }
    }

  }

  if $manage_service {
    if $global_options['chroot'] {
      $deps = [
        Concat['/etc/haproxy/haproxy.cfg'],
        File[$global_options['chroot']],
      ]
    } else {
      $deps = [
        Concat['/etc/haproxy/haproxy.cfg'],
      ]
    }

    service { 'haproxy':
      ensure     => $enable ? {
        true  => running,
        false => stopped,
      },
      enable     => $enable ? {
        true  => true,
        false => false,
      },
      name       => 'haproxy',
      hasrestart => true,
      hasstatus  => true,
      require    => $deps,
      restart    => $restart_command,
    }
  }
}
