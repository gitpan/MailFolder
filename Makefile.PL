#!/usr/bin/perl     # -*-perl-*-

use ExtUtils::MakeMaker;

WriteMakefile(
	      NAME     => 'Mail',
	      VERSION  => '0.01',
	      DISTNAME => 'MailFolder',
	      'dist'   => { COMPRESS => 'gzip', SUFFIX => '.gz'},
);
