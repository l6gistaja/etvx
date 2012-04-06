#!/usr/bin/perl

use strict;
use Data::Dumper;
use UI::Dialog;
use Getopt::Std;

use DBI;
# you also need DBD:SQLite;
use Date::Calc qw(Today Day_of_Week Add_Delta_Days);

use File::Fetch; # for downloading things (bad HTML)
use HTML::TreeBuilder; # for turning bad HTML to X(HT)ML
use XML::Simple; # for parsing X(HT)ML

my @widgets = qw(gdialog cdialog whiptail kdialog zenity xdialog);

use vars qw/ %opt /;
getopts( 'hw:', \%opt );
if ($opt{h}) {
    print "\nUsage:\n-w key forces use of certain widget ("
        .join(', ',@widgets)
        .").\nExample:\n./schedule_etvx.pl -w cdialog\n\n";
    exit;
}


my $dbh = DBI->connect("dbi:SQLite:development.sqlite3", "", "",
{RaiseError => 1, AutoCommit => 1});

############## Configuration from DB

my %cfg = qw();
my $sth = $dbh->prepare("SELECT name, fvalue FROM configuration WHERE category='perlCfg'");
$sth->execute();
while(my $result = $sth->fetchrow_hashref()) {
    $cfg{$result->{'name'}} = $result->{'fvalue'};
}
$sth->finish();

############## Configurate UI
my $certainwidget = 0;
if ($opt{w}) {
    foreach(@widgets) {
        if($_ eq $opt{w}) {
            $certainwidget = 1;
        }
    }
}
my %uiDialog = ('order' => $certainwidget ? [$opt{w}] : @widgets);
my $sth = $dbh->prepare("SELECT name, fvalue FROM configuration WHERE category='UI::Dialog'");
$sth->execute();
while(my $result = $sth->fetchrow_hashref()) {
    $uiDialog{$result->{'name'}} = $result->{'fvalue'};
}
$sth->finish();

############## Channels

my %channels = qw();
my $selected_channel = -1;
$sth = $dbh->prepare("SELECT * FROM channels ORDER BY name");
$sth->execute();
while(my $result = $sth->fetchrow_hashref()) {
    if($selected_channel == -1) { $selected_channel = $result->{'id'}; }
    $channels{$result->{'id'}} = $result;
}
$sth->finish();
#print Dumper(%channels);

############### Today

my @timeData = localtime(time);
my %today = (
    'y' => 1900 + $timeData[5],
    'm' => 1+$timeData[4],
    'd' => $timeData[3]
);
my %cdate = %today;
#print Dumper(%today);

############## Search filter

my @searchFilter = [
    'D', 'Downloaded' , [
        '0', 'Ignore',
        'N', 'No',
        'Y', 'Yes'
    ],
    'T', 'Brodcast\'s time' , [
        '0', 'Ignore',
        'Y', 'Selected year',
        'M', 'Selected month',
        'D', 'Selected date',
        'F', 'In future',
        'P', 'In past'
    ],
    'C', 'Channel' , [
        '0', 'Ignore',
        'S', 'Selected channel'
    ],
];

my $d = new UI::Dialog (%uiDialog);


my $m = "NOT_EXIT";
my $cont = 1;
my $msg = '';
my @ps_output = qw();
my $ps_cmd = "ps aux | grep Schedule::Cron | grep -v 'grep Schedule::Cron' | awk '{print \$2,\$9,\$11,\$12,\$13,\$14,\$15,\$16,\$17,\$18,\$19,\$20,\$21,\$22,\$23,\$24,\$25}'";
my $downloadjuststarted = 0;

while ($m ne "Q" && $cont) {

  @ps_output = `$ps_cmd`;
  
  # our main menu...
  $m = $d->menu(
         'title'=>'Scheduler\'s main menu ('.sprintf($cfg{'dateFormat'},$cdate{'y'},$cdate{'m'},$cdate{'d'}).')',
         'text'=>$msg,
         'list'=>[
            'A','Add broadcasts to queue ',
            'W','Broadcast\'s webpages (if using this with Xserver)',
            'R','Remove scheduled broadcasts from queue ',
            'S','Search scheduled broadcasts by name ',
            'C','Choose channel (currently '.$channels{$selected_channel}->{
            'name'}.') ',
            'M','Choose day from current month ',
            'I','Input day ',
            'T','Today ('.sprintf($cfg{'dateFormat'},$today{'y'},$today{'m'},$today{'d'}).') ',
            'K', (($#ps_output > -1) || $downloadjuststarted ? 'Restart downloader' : 'Start downloader' ),
            'D','Delete cache ',
            'X','Database cleanup',
            'H','Help / About / Readme ',
            'Q','Quit the scheduler '
            ],
        );
        
   $downloadjuststarted = 0;
   $msg = '';
   
   if ($d->state() eq "CANCEL") { $cont = 0; }
   
   if ($d->state() eq "OK") {

################################################################################

    if ($m eq "C") {
        
        my @channelsmenu = qw();
        foreach my $cv (values %channels) {
            push @channelsmenu, $cv->{'id'};
            push @channelsmenu, $cv->{'name'};
        }
        my $channelschoice = $d->menu('title'=>'Choose channel (currently '.$channels{$selected_channel}->{
            'name'}.')',
         'list'=>\@channelsmenu,
        );
        if($channelschoice) { 
            $selected_channel = $channelschoice;
            $msg = 'Channel changed to '.$channels{$selected_channel}->{
            'name'}.'.';
        }
################################################################################

    } elsif ($m eq "H") {

        $d->textbox( 'title'=>'Help / About / Readme', 'path' => 'readme.txt');

################################################################################
    } elsif ($m eq "X") {

        if($d->yesno(
                        title  => 'Confirm database cleanup',
                        text => 'Do you really want to DELETE all broadcasts and downloads history?',
        )) {
            $sth = $dbh->prepare('DELETE FROM crondaemons;');
            $sth->execute();
            $sth = $dbh->prepare('DELETE FROM broadcasts;');
            $sth->execute();
            $msg = 'Broadcasts and download history deleted.';
        }

################################################################################
    } elsif ($m eq "K") {
    
        @ps_output = `$ps_cmd`;
        
        if($#ps_output > -1) {
        
            my @pscronids = qw();
            foreach (@ps_output) {
                    my @tmp = split /\s/, $_;
                    push @pscronids, $tmp[0];
            }
            my $tmpps = join("| ",@ps_output);
            $tmpps =~s/\s+$//g;
            
            my $additionalinfo = '';
            if($#pscronids == 0) {

                my $sth = $dbh->prepare('SELECT exittime, broadcastids FROM crondaemons WHERE pid=?;');
                $sth->execute($pscronids[0]);
                my $result = $sth->fetchrow_hashref();
                $sth->finish();
                
                if($result->{'exittime'} > 0) {
                    $additionalinfo = ' Process '.$pscronids[0].' should have done its already, so its safe to end it.';
                } else {
                    
                    my $sth = $dbh->prepare('SELECT strftime(\'%Y-%m-%d %H:%M\',max(t0ts)+60,\'unixepoch\') AS dlerexit, strftime(\'%Y-%m-%d %H:%M\',min(t0ts),\'unixepoch\') AS dlerstart, datetime(\'now\',\'localtime\') AS timenow FROM broadcasts WHERE id IN ('.$result->{'broadcastids'}.');');
                    $sth->execute();
                    if($result = $sth->fetchrow_hashref()) {
                        $additionalinfo = ' Process '.$pscronids[0].' shouldnt be stopped between '.$result->{'dlerstart'}.' and '.$result->{'dlerexit'}.', current time is '.substr($result->{'timenow'},0,16).' .';
                    }
                    $sth->finish();
                }
            
            }
            
            if($d->yesno( 'title' => 'Warning: older active downloads',
                'text' => "Process table shows active older downloads:\n\n"
                .$tmpps
                ."."
                .$additionalinfo
                ." Do you want to end process "
                .join(", ",@pscronids)." and start new downloader?"
            )) {
                foreach(@pscronids) { system('kill '.$_);}
                new_downloader();
            }

        } else {
            new_downloader();
        }
    
################################################################################

    } elsif ($m eq "A" || $m eq "W") {
            
        my $xmlfile = sprintf($channels{$selected_channel}->{
            'xml_filetemplate'}, $cdate{'y'},$cdate{'m'},$cdate{'d'});
        my $data = fetch_xml($channels{$selected_channel}->{
            'xml_url'}, $xmlfile);
        my @y = data_etv120229($data);
        #print Dumper(@y);

        my @options = qw();
        
        if ($m eq "A") {

            foreach(@y) {
                my %yi = %{$_};
                push @options, $yi{'t0'};
                push @options, [$yi{'label'}.' ',0];
            }
            
            my @item = $d->checklist(
                'title'=>'Add: '.$channels{$selected_channel}->{
                'name'}.', '.sprintf($cfg{'dateFormat'},$cdate{'y'},$cdate{'m'},$cdate{'d'}),
                'text'=>'Broadcast',
                'list'=>\@options);
            #print Dumper(@item);
            
            my $addedbroadcasts = 0;
            if($#item > -1) {

                $sth = $dbh->prepare('INSERT INTO broadcasts (url,name,channel_id,t0ts,t1ts,created_at,download_started) VALUES (?,?,?,strftime(\'%s\',?),strftime(\'%s\',?),datetime(\'now\',\'localtime\'),0);');
                my $addedBroadcasts = 0;
                my $rejectedBroadcasts = 0;
                
                my $time;
                foreach $time (@item) {
                    if($time =~ /($cfg{'hhmm24Regexp'})/) {
                    
                        $addedbroadcasts++;
                        for(my $i=0; $i < $#y; $i++) {
                            if($time eq $y[$i]->{'t0'}) {
                                
                                my $starttime = sprintf($cfg{'dateFormat'},
                                    $cdate{'y'},$cdate{'m'},$cdate{'d'})
                                    .' '.$y[$i]->{'t0'}.':00';
                                #check that braodcast isnt already added
                                my $sth2 = $dbh->prepare('SELECT count(id) AS c FROM broadcasts WHERE t0ts = strftime(\'%s\',?) AND channel_id = ?');
                                $sth2->execute( $starttime,$selected_channel);
                                my $result = $sth2->fetchrow_hashref();
                                $sth2->finish();
                                
                                if($result->{'c'} > 0) {
                                    $rejectedBroadcasts++;
                                } else {
                                    $addedBroadcasts++;
                                    (my $year, my $month, my $day)  =
                                        Add_Delta_Days($today{'y'},$today{'m'},$today{'d'}, 
                                            $y[$i+1]->{'t0'} < $y[$i+1]->{'t1'} ? 1 : 0);
                                    my $endtime = sprintf($cfg{'dateFormat'},$year,$month,$day)
                                        .' '.$y[$i+1]->{'t0'}.':00';
                                    $sth->execute(
                                        $y[$i]->{'url'},
                                        $y[$i]->{'label'},
                                        $selected_channel,
                                        $starttime,
                                        $endtime
                                    );
                                }
                            }
                        }

                    }
                }
                #print Dumper(@item);
                $sth->finish();
                if ($addedbroadcasts) {
                    $msg = 'Added '.$addedBroadcasts.' new broadcasts to queue, did\'nt add '.$rejectedBroadcasts.' which already existed.';
                }
                
            }

        } elsif ($m eq "W") {
        
            foreach(@y) {
                my %yi = %{$_};
                push @options, $yi{'t0'};
                push @options, $yi{'label'};
            }
            
            while($d->state() ne "CANCEL") {
                $m = $d->menu(
                    'title'=>'Links to broadcasts: '.$channels{$selected_channel}->{
                'name'}.', '.sprintf($cfg{'dateFormat'},$cdate{'y'},$cdate{'m'},$cdate{'d'}),
                    'list'=> \@options
                    );
                if($m =~ /($cfg{'hhmm24Regexp'})/) {
                    foreach(@y) {
                        my %yi = %{$_};
                        if($yi{'t0'} eq $m) {
                            system($cfg{'webbrowser'}.' '.$yi{'url'}.' &');
                        }
                    }
                }
            }
            
        }

################################################################################

    } elsif ($m eq "S") {
    
            my $item = $d->inputbox('title'=>'Search scheduled broadcasts by name');
            
            while($d->state() ne "CANCEL") {
                my $searchstr = $item;
                $searchstr =~s/\'//g;
                my @options = search_results('b.name LIKE \'%'.$searchstr.'%\'','menu');
                
                if($#options > -1) {
                    do {
                        $m = $d->menu(
                            'title'=>'Search broadcasts: '.$searchstr,
                            'list'=> \@options
                        );
                        
                        if($m =~/^\d+$/ && $m ne '0') { 
                            showbroadcast($m);
                            #if selected broadcast was deleted, search again
                            @options = search_results('b.name LIKE \'%'.$searchstr.'%\'','menu');
                        }
                    } while ( $m =~/^\d+$/ && $m ne '0' );
                }
                
                if($d->state() ne "CANCEL") {
                    $item = $d->inputbox(
                        'title'=>'Search scheduled broadcasts by name',
                        'text' => '('
                            .( $#options < 0 ? 'Nothing found. ' : '')
                            .'Previous search was: \''.$searchstr.'\')'
                    );
                }
            }

################################################################################

    } elsif ($m eq "R") {
        
        my @options = search_results('b.t0ts >= strftime(\'%s\',\''
            .sprintf($cfg{'dateFormat'},$cdate{'y'},$cdate{'m'},$cdate{'d'})
            .' 00:00:00\') AND b.t0ts <= strftime(\'%s\',\''
            .sprintf($cfg{'dateFormat'},$cdate{'y'},$cdate{'m'},$cdate{'d'})
            .' 23:59:59\')',
            
            'checklist');
        
        my @item = $d->checklist(
            'title'=>'Delete scheduled broadcasts ('.sprintf($cfg{'dateFormat'},$cdate{'y'},$cdate{'m'},$cdate{'d'}).')',
            'text'=>'Broadcast',
            'list'=>\@options);
            
        if($#item > -1) {
            $sth = $dbh->prepare('DELETE FROM broadcasts WHERE id IN ('.join(',',@item).')');
            $sth->execute();
            $sth->finish();
            $msg = ($#item + 1) .' broadcasts deleted.';
        }
            
################################################################################

    } elsif ($m eq "M") {
        
        my @weekdays = qw(Mon Tue Wed Thu Fri Sat Sun);
        my @options = qw();
        for(my $i=-14;$i<15;$i++) {
            (my $year, my $month, my $day) = Add_Delta_Days($today{'y'},$today{'m'},$today{'d'}, $i);
            my $md = sprintf($cfg{'dateFormat'},$year,$month,$day);
            push @options, $md;
            push @options, $weekdays[Day_of_Week($year, $month, $day)-1]
                #.' '.$md 
                .($i==0?' (today) ':'');
        };
        my $item = $d->menu(
            'title'=>'Choose date (currently '.sprintf($cfg{'dateFormat'},$cdate{'y'},$cdate{'m'},$cdate{'d'}).') ',
            'list'=>\@options);
            
        $msg = set_date($item);

################################################################################

    } elsif ($m eq "I") {
        
        
        my $item = $d->inputbox(
            'title'=>'Choose day',
            'text'=>'Currently '.sprintf($cfg{'dateFormat'},$cdate{'y'},$cdate{'m'},$cdate{'d'})
            );
        $msg = set_date($item);
        
################################################################################

    } elsif ($m eq "T") {
    
        %cdate = %today;
        $msg = 'Date changed to today.';
        
################################################################################

    } elsif ($m eq "D") {
    
        system('rm '.$cfg{'cacheDir'}.$cfg{'dirDelimiter'}.'*');
        $msg = 'Cache deleted.';
        
    }
    
  }
}

############### SUBMERGE ############### SUBMERGE ############### SUBMERGE

sub new_downloader {
    if (my $pid = fork) {
        $msg = 'New downloader ('.$pid.') started.';
    } else {
        exec('./kron_etvx.pl &> /dev/null');
    }
    @ps_output = `$ps_cmd`;
    $downloadjuststarted = 1;
}

sub search_results {
        my @sroptions = qw();
        my $srsql = 'SELECT b.id AS bid, b.name AS bname, strftime(\'%Y-%m-%d\',b.t0ts,\'unixepoch\') AS day, strftime(\'%H:%M\',b.t0ts,\'unixepoch\')  AS time0, strftime(\'%H:%M\',b.t1ts,\'unixepoch\') AS time1, c.name AS cname, b.download_started FROM broadcasts b, channels c WHERE '.$_[0].' AND b.channel_id=c.id ORDER BY b.t0ts, c.name';
        #print $srsql;
        $sth = $dbh->prepare($srsql);
        $sth->execute();

        while(my $result = $sth->fetchrow_hashref()) {
            my $srlabel = $result->{'day'}
                .' '.$result->{'time0'}
                .'...'.$result->{'time1'}
                .' @'.$result->{'cname'}
                .' '.$result->{'bname'}
                .($result->{'download_started'} == 1 ? ' '.$cfg{'downloadSymbol'}: '')
                .' ';
            $cfg{$result->{'name'}} = $result->{'fvalue'};
            push @sroptions, $result->{'bid'};
            push @sroptions, ($_[1] eq 'checklist' ? [$srlabel,0] : $srlabel);
        }
        $sth->finish();
        #print Dumper(@sroptions);
        return @sroptions;
}

sub set_date {
    if($_[0] =~/^\d+-(02-[0-2]\d|(0[469]|11)-([0-2]\d|30)|(0[13578]|1[02])-([0-2]\d|3[01]))$/)
    {
        my @dp = split(/-/, $_[0]);
        $dp[1] =~s/^0//;
        $dp[2] =~s/^0//;
        $cdate{'y'} = $dp[0];
        $cdate{'m'} = $dp[1];
        $cdate{'d'} = $dp[2];
        return 'Date changed to '.$_[0].'.';
    } else { return ''; }
}


sub fetch_xml {
    
    # cache during one session
    if(!(-e $cfg{'cacheDir'}.$cfg{'dirDelimiter'}.$_[1])) {
        my $ff = File::Fetch->new(uri => $_[0].$_[1]);
        my $where = $ff->fetch('to' => $cfg{'cacheDir'}) or die $ff->error;
    }
    
    my $xmlfile = sprintf($cfg{'cacheFilenameFormat'},
        $cdate{'y'},$cdate{'m'},$cdate{'d'},
        $selected_channel);
    
    if(!(-e $cfg{'cacheDir'}.$cfg{'dirDelimiter'}.$xmlfile)) {
        # cleans utf8 shitty html to utf8 xhtml (often)
        my $tree = HTML::TreeBuilder->new; # empty tree
        $tree->parse_file($cfg{'cacheDir'}.$cfg{'dirDelimiter'}.$_[1]);
        open (INDEXFILE2, ">", $cfg{'cacheDir'}.$cfg{'dirDelimiter'}.$xmlfile);
        #binmode INDEXFILE2, ":utf8";
        print INDEXFILE2 $tree->as_XML;
        close(INDEXFILE2);
        $tree = $tree->delete;
    }
    
    # create object
    my $xml = new XML::Simple;
    
    # read XML file
    return $xml->XMLin($cfg{'cacheDir'}.$cfg{'dirDelimiter'}.$xmlfile);
}

sub showbroadcast {
    my $bcui = new UI::Dialog (%uiDialog);
    my $bcui2 = new UI::Dialog (%uiDialog);
    my $deleted = 0;
    my $msg = '';
    my $bcid = $_[0];
    
    while ($bcui->state() ne "CANCEL" && !$deleted) {
        
        my $sth2 = $dbh->prepare('SELECT b.name AS bname, strftime(\'%Y-%m-%d\',b.t0ts,\'unixepoch\') AS day, strftime(\'%H:%M\',b.t0ts,\'unixepoch\')  AS time0, strftime(\'%H:%M\',b.t1ts,\'unixepoch\') AS time1, strftime(\'%s\',datetime(\'now\',\'localtime\')) AS timenow, b.t1ts, c.name AS cname, b.download_started, b.url, b.description, b.filename, c.flv_directory, c.watch_url FROM broadcasts b, channels c WHERE b.id = ? AND b.channel_id=c.id');
        $sth2->execute($bcid);
        my $result = $sth2->fetchrow_hashref();
        
        my $shortdescr = $result->{'description'};
        $shortdescr =~s/\s+/ /mg;
        $shortdescr =~s/^\s+//;
        $shortdescr =~tr/"/'/;
        $shortdescr = substr $shortdescr, 0, 65;
        #print Dumper($result);
        
        my $aired = $result->{'day'}.' '.$result->{'time0'}.'...'.$result->{'time1'}.' @ '.$result->{'cname'};
        
        my @bcoptions = [
            'Name', $result->{'bname'}.' ',
            'Aired', $aired.' ',
            'URL', $result->{'url'},
            'Description', $shortdescr.'... ',
            'Download', $result->{'download_started'} eq '1' ?
                ($result->{'timenow'} > $result->{'t1ts'} ?
                    'Download finished'
                        .($result->{'watch_url'} =~/[^\s]+/ ? ', watch' : '')
                    :'Download started')
                : 'Not downloaded',
            'Filename', $result->{'filename'},
            'Erase', ' [Erase it from database] ',
            'Delete', ' [Erase it from database and also try to delete downloaded file] '
        ];

        my $bcuim = $bcui->menu(
         'title'=>'Broadcast',
         'text'=>$msg,
         'list'=> @bcoptions
        );
        $msg = '';
        
        if($bcuim eq 'URL' && $result->{'url'} =~/[^\s]+/) {
            system($cfg{'webbrowser'}.' '.$result->{'url'}.' &');
            $msg = 'Webpage opened.';
        } elsif($bcuim eq 'Aired' && $result->{'description'} =~/[^\s]+/) {
            $bcui2->msgbox('title' => 'Description', 'text' => $result->{'description'});
        } elsif($bcuim eq 'Name') {
            my $answer = $bcui2->inputbox(
                            title  => 'Change broadcast name',
                            text => ''.$result->{'bname'},
                            entry => $result->{'bname'}
                            );
            if($answer && $answer =~/[^\s]+/) {
                $answer =~ s/\R/ /g;
                $sth2 = $dbh->prepare('UPDATE broadcasts SET updated_at=strftime(\'%s\',datetime(\'now\',\'localtime\')), name=? WHERE id=?;');
                $sth2->execute($answer, $bcid);
                $msg = 'Name changed.';
            }
            
        } elsif($bcuim eq 'Description') {
            my $answer = $bcui2->inputbox(
                            title  => 'Change broadcast description',
                            text => ''.$result->{'description'},
                            entry => $result->{'description'}
                            );
            if($answer && $answer =~/[^\s]+/) {
                $answer =~ s/\R/ /mg;
                #$answer =~ s/\s/ /mg;
                $sth2 = $dbh->prepare('UPDATE broadcasts SET updated_at=strftime(\'%s\',datetime(\'now\',\'localtime\')), description=? WHERE id=? ');
                $sth2->execute($answer, $bcid);
                $msg = 'Description changed.';
            }
            
        } elsif($bcuim eq 'Erase' || $bcuim eq 'Delete') {
            if($bcui2->yesno(
                            title  => 'Confirm erase',
                            text => 'Do you really want to delete broadcast named '
                            .$result->{'bname'}
                            .', aired '
                            .$aired
                            .($bcuim eq 'Delete' 
                                ? ', and also delete downloaded file '.$result->{'filename'} : '')
                            .'?'
            )) {
                $sth2 = $dbh->prepare('DELETE FROM broadcasts WHERE id=?;');
                $sth2->execute($bcid);
                $deleted = 1;
                if($bcuim eq 'Delete') {
                    system('rm '.$result->{'flv_directory'}.$result->{'filename'});
                }
            }
        } elsif($bcuim eq 'Filename' && $result->{'filename'}=~/[^\s]+/) {
            $bcui2->msgbox(
                            title  => 'Downloaded FLV filename',
                            text => 'FLV filename is '.$result->{'filename'}
                            .' and it is probably in directory '.$result->{'flv_directory'}
            );
        } elsif($bcuim eq 'Download'
            && $result->{'download_started'} eq '1'
            && $result->{'timenow'} > $result->{'t1ts'}
            && $result->{'watch_url'} =~/[^\s]+/
        ) {
            system($cfg{'webbrowser'}.' \''
                .sprintf($result->{'watch_url'},$result->{'filename'}).'\' &');
            $msg = 'Webplayer opened.';
        }
        
    }

}

sub data_etv120229 {
    my $data = $_[0];
    my @y = qw();
    foreach (@{$data->{body}->{div}->{h3}}) {
        my $yi = {};
        $yi->{'t0'} = $_->{span}->{content};
        $yi->{'label'} = $_->{a}->{content};
        $yi->{'url'} = $_->{a}->{href};
        push @y, $yi;
    }
    return @y;
}

$dbh->disconnect;
$d->clear;
exit;

