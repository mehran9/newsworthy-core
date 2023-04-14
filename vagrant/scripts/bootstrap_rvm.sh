#!/usr/bin/env bash

cd /home/vagrant
gpg --keyserver hkp://keys.gnupg.net --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3
\curl -sSL https://get.rvm.io | bash -s stable

source /home/vagrant/.profile
source /home/vagrant/.rvm/scripts/rvm

rvm install 2.2.4
rvm use 2.2.4 --default
gem install bundler

source /home/vagrant/.bashrc
source /home/vagrant/.bash_profile
source /home/vagrant/.profile

sudo update-alternatives --install /usr/bin/ruby ruby /home/vagrant/.rvm/rubies/ruby-2.2.4/bin/ruby 1
