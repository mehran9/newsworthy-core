# Make sure apt-get -y update runs before anything else.
stage { 'preinstall':
  before => Stage['main']
}

class apt_get_update {
  exec { '/usr/bin/apt-get -y update':
    user => 'root'
  }
}

class { 'apt_get_update':
  stage => preinstall
}

package {
  [
    'build-essential',
    'zlib1g-dev',
    'libssl-dev',
    'libreadline-dev',
    'git-core',
    'curl',
    'libmagickwand-dev',
    # 'libmysqlclient-dev',
    'imagemagick',
    'ntp'
  ]:
  ensure => installed
}


class mongodb {
  exec { "10genKeys":
    command => "sudo apt-key adv --keyserver keyserver.ubuntu.com --recv 7F0CEB10",
    path => ["/bin", "/usr/bin"],
    notify => Exec["apt_get_update"],
    unless => "apt-key list | grep 10gen"
  }

  file { "10gen.list":
    path => "/etc/apt/sources.list.d/10gen.list",
    ensure => file,
    content => "deb http://downloads-distro.mongodb.org/repo/debian-sysvinit dist 10gen",
    notify => Exec["10genKeys"]
  }

  package { "mongodb-10gen":
    ensure => present,
    require => [Exec["apt_get_update"],File["10gen.list"]]
  }

}

include mongodb

# class { "mysql":
#   root_password => ''
# }
#
# include mysql
