#!/usr/bin/perl

use ExtUtils::MakeMaker;

WriteMakefile(
	      NAME     => 'Mail',
	      VERSION  => '0.05',
	      DISTNAME => 'MailFolder',
	      PREREQ_PM => { Mail::Internet => 1.28,
			     File::BasicFlock => 96.042302,
			     Date::Format => 2.07,
			     File::Sync => 0.04,
			     },
	      'dist'   => { COMPRESS => 'gzip', SUFFIX => '.gz' },
);

sub MY::test {
  q(
TEST_VERBOSE=0

test:
	$(FULLPERL) t/TEST $(TEST_VERBOSE)
);
}
