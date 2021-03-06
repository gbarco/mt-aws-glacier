#!/usr/bin/perl

# mt-aws-glacier - Amazon Glacier sync client
# Copyright (C) 2012-2013  Victor Efimov
# http://mt-aws.com (also http://vs-dev.com) vs@vs-dev.com
# License: GPLv3
#
# This file is part of "mt-aws-glacier"
#
#    mt-aws-glacier is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    mt-aws-glacier is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.

use strict;
use warnings;
use utf8;
use Test::More tests => 6;
use Test::Deep;
use lib qw{../lib ../../lib};
use App::MtAws::ConfigEngine;
use Test::MockModule;
use Data::Dumper;

no warnings 'redefine';

local *App::MtAws::ConfigEngine::read_config = sub { { key=>'mykey', secret => 'mysecret', region => 'myregion' } };

my %disable_validations = ( 
	'override_validations' => {
		'journal' => [ ['Journal file not exist' => sub { 1 } ], ],
	},
);



# v0.85 regressions test


my ($default_concurrency, $default_partsize) = (4, 16);

# create-vault

for (
	qq!create-vault myvault --config=glacier.cfg!,
){
	my ($errors, $warnings, $command, $result) = App::MtAws::ConfigEngine->new(%disable_validations)->parse_options(split(' ', $_));
	ok( !$errors && !$warnings, "$_ error/warnings");
	ok ($command eq 'create-vault', "$_ command");
	is_deeply($result, {
		key=>'mykey',
		secret => 'mysecret',
		region => 'myregion',
		protocol => 'http',
		'vault-name'=>'myvault',
		config=>'glacier.cfg',
	}, "$_ result");
}


# delete-vault

for (
	qq!delete-vault myvault --config=glacier.cfg!,
){
	my ($errors, $warnings, $command, $result) = App::MtAws::ConfigEngine->new(%disable_validations)->parse_options(split(' ', $_));
	ok( !$errors && !$warnings, "$_ error/warnings");
	ok ($command eq 'delete-vault', "$_ command");
	is_deeply($result, {
		key=>'mykey',
		secret => 'mysecret',
		region => 'myregion',
		protocol => 'http',
		'vault-name'=>'myvault',
		config=>'glacier.cfg',
	}, "$_ result");
}



1;