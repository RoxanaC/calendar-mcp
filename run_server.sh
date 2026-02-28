#!/bin/bash
source "$HOME/.rvm/scripts/rvm"
rvm use ruby-3.3.4 > /dev/null 2>&1
cd "$(dirname "$0")"
exec bundle exec ruby calendar_server.rb
