#!/usr/bin/perl     # -*-perl-*-

use ExtUtils::MakeMaker;

WriteMakefile(
	      NAME     => 'Mail',
	      VERSION  => '0.03',
	      DISTNAME => 'MailFolder',
	      'dist'   => { COMPRESS => 'gzip', SUFFIX => '.gz'},
);
