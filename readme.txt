Scripts for automatic scheduling and downloading Estonian TV live streams
    (http://otse.err.ee) with Linux, Perl and SQLite3, 2012-03-04.

For quickstart, enter etvx directory and type to commandline
    ./schedule_etvx.pl
or
    ./schedule_etvx.pl -h

Some kind of RTMP downloader should be used, for that reason compiled
(without SSL support, make XDEF=-DNO_SSL) rtmpdump was included into this
package. About RTMPDump, see http://rtmpdump.mplayerhq.hu .

Exact download Bash command can be configured in SQLite DB table
configuration where category = 'perlCfg' and name = 'downloadCommandFormat':
    %1$d is download length in seconds;
    %2$s is stream url (DB column channels.stream_url);
    %3$s is output filename template (DB columns channels.flv_directory
        + channels.flv_filetemplate, 
            where %1$s is broadcast's datetime of beginning).

ETV's RTMP stream's URLs can be seen from:
    http://otse.err.ee/xml/etv.js
    http://otse.err.ee/xml/etv2.js

Program schedule's HTML URLs can be combined by concatenating DB columns
channels.xml_url and channels.xml_filetemplate.

Developed and tested with:
    Linux kernel 2.6.26-2-686
    Perl v5.10.0 built for i486-linux-gnu-thread-multi
    SQLite 3
    GNU bash, version 3.2.39(1)-release (i486-pc-linux-gnu)

Perl modules needed:
 Date::Calc
 DBD:SQLite3
 DBI
 File::Fetch
 Getopt::Std
 HTML::TreeBuilder
 Schedule::Cron
 UI::Dialog
 XML::Simple

License: BSD 3-Clause License http://www.opensource.org/licenses/BSD-3-Clause
Author: juks@alkohol.ee
