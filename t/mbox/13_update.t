#!/usr/bin/perl       # -*-perl-*-

require 't/mbox.pl';

print "1..12\n";

okay_if(1, $folder = new Mail::Folder('mbox', full_folder()));
okay_if(2, $folder->add_label(1, 'greeble'));
okay_if(3, $message = $folder->get_message(1));
okay_if(4, $message->replace('subject', 'zoink'));
okay_if(5, $folder->update_message(1, $message));
okay_if(6, $folder->sync == 0);
okay_if(7, $folder->label_exists(1, 'greeble'));
okay_if(8, $folder->close);

okay_if(9, $folder = new Mail::Folder('mbox', full_folder()));
okay_if(10, $message = $folder->get_header(1));
okay_if(11, $message->get('subject') eq "zoink\n");
okay_if(12, $folder->close);

1;
