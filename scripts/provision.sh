#!/bin/bash

RUBY_VERSION=2.3.0
RAILS_VERSION=4.2.5
PG_VERSION=9.5

################################################################################
# Add custom repositories
################################################################################
apt-get install -y apt-transport-https ca-certificates

curl -s https://deb.nodesource.com/gpgkey/nodesource.gpg.key | apt-key add -
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 561F9B9CAC40B2F7

apt-add-repository multiverse                                                # Multiverse
add-apt-repository https://deb.nodesource.com/node_0.12/                     # NodeJS repository
add-apt-repository https://oss-binaries.phusionpassenger.com/apt/passenger   # Passenger

# Sane update/upgrade.
apt-get -y update
apt-get -y upgrade

################################################################################
# Install basic requirements and utilities
################################################################################

apt-get -y install build-essential curl gdb git-core htop imagemagick libcurl4-openssl-dev \
        libffi-dev libreadline-dev libsqlite3-dev libssl-dev libxml2-dev libxslt1-dev \
        libyaml-dev libz-dev linux-tools-generic lsb-release openssl python-software-properties \
        rar rlwrap sbcl screen scrot silversearcher-ag sqlite3 subversion systemtap tree unrar \
        unzip valgrind vim zip zlib1g zlib1g-dev zsh

################################################################################
# Archey :)
################################################################################
wget --quiet http://github.com/downloads/djmelik/archey/archey-0.2.8.deb
dpkg -i archey-0.2.8.deb
rm archey-0.2.8.deb

################################################################################
# Function to run rbenv commands
################################################################################
execute_with_rbenv () {
    `cat >/home/vagrant/temp-script.sh <<\EOF
export HOME=/home/vagrant
if [ -d $HOME/.rbenv ]; then
  export PATH="$HOME/.rbenv/bin:$PATH"
  eval "$(rbenv init -)"
fi

EOF
`
    echo $1 >> /home/vagrant/temp-script.sh
    chmod +x /home/vagrant/temp-script.sh
    su vagrant -c "bash -c /home/vagrant/temp-script.sh"
    rm /home/vagrant/temp-script.sh
}

install_ruby_and_bundler () {
    execute_with_rbenv "rbenv install $1"
    execute_with_rbenv "rbenv local $1"
    execute_with_rbenv "gem install bundler"
}

################################################################################
# Install rbenv
################################################################################
`cat >/home/vagrant/install_rbenv.sh <<\EOF
git clone https://github.com/sstephenson/rbenv.git ~/.rbenv
git clone https://github.com/sstephenson/ruby-build.git ~/.rbenv/plugins/ruby-build
echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bash_profile
echo 'eval "$(rbenv init -)"' >> ~/.bash_profile
EOF
`
chmod +x /home/vagrant/install_rbenv.sh
su vagrant -c "bash -c /home/vagrant/install_rbenv.sh"
rm /home/vagrant/install_rbenv.sh

################################################################################
# Install ruby
################################################################################
install_ruby_and_bundler "$RUBY_VERSION"
execute_with_rbenv "rbenv global $RUBY_VERSION"

################################################################################
# Install NodeJS
################################################################################
apt-get -y install nodejs
npm install npm -g

################################################################################
# Install PostgreSQL
################################################################################
echo 'deb http://apt.postgresql.org/pub/repos/apt/ trusty-pgdg main 9.5' | sudo tee -a '/etc/apt/sources.list.d/postgresql.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
apt-get update
apt-get install -y postgresql postgresql-contrib-9.5 postgresql-client-9.5 libpq-dev

sudo -u postgres pg_dropcluster --stop $PG_VERSION main
sudo -u postgres pg_createcluster --start $PG_VERSION main
sudo -u postgres createuser -d -R -w -S vagrant
perl -i -p -e 's/local   all             all                                     peer/local all all trust/' /etc/postgresql/$PG_VERSION/main/pg_hba.conf

service postgresql restart

################################################################################
# Install Passenger
################################################################################
apt-get install -y passenger nginx-extras

`cat >/etc/nginx/sites-available/blog <<\EOF
server {
    server_name *.lvh.me;

    listen 3000;

    client_max_body_size 10M;

    passenger_enabled on;

    rails_env    development;
    root         /vagrant/blog/public;

    # redirect server error pages to the static page /50x.html
    error_page   500 502 503 504  /50x.html;
    location = /50x.html {
        root   html;
    }
}
EOF
`

perl -i -p -e 's/# passenger_root \/usr\/lib\/ruby\/vendor_ruby\/phusion_passenger\/locations\.ini\;\n/passenger_root \/usr\/lib\/ruby\/vendor_ruby\/phusion_passenger\/locations.ini;\n\tpassenger_ruby \/home\/vagrant\/.rbenv\/shims\/ruby;\n/' /etc/nginx/nginx.conf

ln -s /etc/nginx/sites-available/blog /etc/nginx/sites-enabled/blog
rm /etc/nginx/sites-enabled/default

service nginx restart

################################################################################
# Basic environment setup
################################################################################
echo "shark-devenv" > /etc/hostname
echo "127.0.0.1 shark-devenv" >> /etc/hosts
hostname shark-devenv

`cat >/home/vagrant/.environment.sh <<\EOF
# Environment variables
export LANG="en_US.UTF-8"
export PS1="[\[\033[1;35m\]\u\[\033[0m\]@\[\033[36m\]\h\[\033[0m\]:\[\033[1;37m\]\w\[\033[0m\]]$ "

alias get-repositories='bash /vagrant/scripts/get-repositories.sh'
alias ls="ls --color=auto"
alias grep='grep --color=auto'
alias egrep='egrep --color=auto'
alias fgrep='fgrep --color=auto'
alias glog='git log --oneline --decorate --graph'
export CLICOLOR="YES"

alias api-recreate-db='bundle exec rake db:setup'
alias api-server='bundle exec rails server -b 0.0.0.0'
alias api-db='bundle exec rails dbconsole'
alias api-console='bundle exec rails console'
alias api-restart='touch /vagrant/blog/tmp/restart.txt'

# Load secret keys, if any.
if [ -f ~/.secret_keys.sh ]; then
  source ~/.secret_keys.sh
fi

archey

EOF
`

echo 'source ~/.environment.sh' >> /home/vagrant/.bash_profile

touch /home/vagrant/.secret_keys.sh

chown vagrant:vagrant /home/vagrant/.environment.sh
chown vagrant:vagrant /home/vagrant/.secret_keys.sh

################################################################################
# Cleanup
################################################################################
apt-get -y autoremove
apt-get -y autoclean
apt-get -y clean

################################################################################
# Welcome screen
################################################################################
echo "#####################################################################################"
echo "# Welcome to the Shark project development environment!                              "
echo "#                                                                                    "
echo "# Info:                                                                              "
echo "# PostreSQL user 'vagrant' created without password. 'stores' database created.      "
echo "#                                                                                    "
echo "#####################################################################################"
