package xCAT_plugin::novadns;
BEGIN { $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat'; }
use lib "/opt/xcat/lib/perl/";
use strict;
use Getopt::Long;
use xCAT::Table;
use xCAT::NetworkUtils qw/getipaddr/;
use xCAT::SvrUtils;
use JSON::XS;
use URI::URL;

sub handled_commands
{
    return {"makedns" => "site:dnshandler"};
}

sub process_request {
    my ($request, $callback) = @_;
    @ARGV=@{$request->{arg}||[]};
    my ($allnodes, $zapzone, $deletemode, $help, %seenzones);

    Getopt::Long::Configure("no_pass_through");
    Getopt::Long::Configure("bundling");
    if (!GetOptions(
            'a|all' => \$allnodes,
            'n|new' => \$zapzone,
            'd|delete' => \$deletemode,
            'h|help' => \$help,) or $help) 
        {
            makedns_usage($callback);
            return;
        }

    if ($allnodes) {
        #TODO read all nodelist specified nodes
        xCAT::SvrUtils::sendmsg([1,"allnode mode not supported"],$callback);
        return;
    } 

    my $sitetab = xCAT::Table->new('site');
    my $networkstab = xCAT::Table->new('networks',-create=>0);
    unless ($networkstab) { 
        xCAT::SvrUtils::sendmsg([1,'Unable to enumerate networks, try to run makenetworks'], $callback);
        return
    }
    my $hoststab = xCAT::Table->new('hosts',-create=>0);
    unless ($hoststab) {
        xCAT::SvrUtils::sendmsg([1,"table 'hosts' empty"],$callback);
        return;
    }
    my $passtab = xCAT::Table->new('passwd');
    my $pent = $passtab->getAttribs({key=>'novadns_url',username=>'xcat_key'},['password']);
    unless ($pent and $pent->{password}) {
        xCAT::SvrUtils::sendmsg([1,'Please add novadns_url in passwd table'], $callback);
        return;
    } #do not warn/error here yet, if we can't generate or extract, we'll know later
    my ($token, $url) = split /@/, $pent->{password}, 2;
    my $stab = $sitetab->getAttribs({key=>'domain'},['value']);
    unless ($stab and $stab->{value}) {
       xCAT::SvrUtils::sendmsg([1,"domain not defined in site table"], $callback);
       return;
    }
    my $domain = $stab->{value};
      
    my @networks = $networkstab->getAllAttribs('net','mask','ddnsdomain');

    my $hosts = $hoststab->getNodesAttribs($request->{node},['ip']);
    for (@{$request->{node}}) {
        next if exists $hosts->{$_};
        xCAT::SvrUtils::sendmsg([0,"`$_`: skipped: not found in hosts table"], $callback);
    }
    
    foreach my $h (keys %{$hosts}) {
        #TODO add validate ip, zone, hostname
        my $ip = $hosts->{$h}->[0]->{ip};
        my $host = lc $h;
        my $zone=lc $domain;
        for (@networks) {
            next if not  xCAT::NetworkUtils->ishostinsubnet($ip, $_->{mask}, $_->{net});
            $zone=lc $_->{ddnsdomain} if $_->{ddnsdomain};
            last;
        }
        my $fqdn = $host ? "$host.$zone" : $zone;
        $host ||= '@';
        #TODO - split in different functions
        if ($deletemode) { 
            warn 1;
            my $res = _request($url, $token, 'DELETE', "/record/$zone/$host/A");
            if ($res->{error}) { 
                warn 2;
                xCAT::SvrUtils::sendmsg([1,"`$fqdn`: error: ".$res->{error}], $callback);
            }
            else { 
                warn 3;
                xCAT::SvrUtils::sendmsg([0,"`$fqdn`: deleted"], $callback);
            }
            next;
        }
        #re-create zone if needed
        if ($zapzone and not exists $seenzones{$zone}) {
            _request($url, $token, 'DELETE', "/zone/$zone", force=>1);
            my $res = _request($url, $token, 'PUT', "/zone/$zone");
            if ($res->{result} eq 'ok') { 
                xCAT::SvrUtils::sendmsg([0,"`$zone`: zone was re-created"], $callback);
                $seenzones{$zone} = undef;
            }
            else { 
                xCAT::SvrUtils::sendmsg([1,
                    "`$zone`: error re-creating zone: ".$res->{error}], $callback);
                $seenzones{$zone} = 1;
            }
        }
        #cache zone content. FIXME race
        if (not $seenzones{$zone}) {
            my $res = _request($url, $token, 'GET', "/record/$zone", 'type'=>'A');
            if ($res->{error}) {
                xCAT::SvrUtils::sendmsg([1, "`$zone`: error: ".$res->{error}], $callback);
                $seenzones{$zone} = 1;
            }
            else {
                $seenzones{$zone} = {map {$_->{name} => $_} @{$res->{result}}};
            }
        }
        #skip records if any problem with zone 
        if ($seenzones{$zone} == 1) { 
            xCAT::SvrUtils::sendmsg([1,"`$fqdn`: skipped: error with zone `$zone`"], $callback);
            next;
        }
        my $res;
        if (exists $seenzones{$zone}{$fqdn}) {
            if ($seenzones{$zone}{$fqdn}{content} eq $ip) { 
                xCAT::SvrUtils::sendmsg([0,"`$fqdn`: skipped: already up to date"], $callback);
                next;
            }
            $res = _request($url, $token, 'POST', "/record/$zone/$host/A", 'content'=>$ip);
        }
        else { 
            $DB::single=2;
            $res = _request($url, $token, 'PUT', "/record/$zone/$host/A/$ip");
        
        }
        if ($res->{error}) {
            xCAT::SvrUtils::sendmsg([1,"`$fqdn`: error: ".$res->{error}], $callback);
        }
        else { 
            xCAT::SvrUtils::sendmsg([0,"`$fqdn`: processed {$ip}"], $callback);
        }
        #TODO PTR
    }
    xCAT::SvrUtils::sendmsg("DNS setup is completed", $callback);
}

sub _request { 
    my ($endpoint, $token, $method, $path, %params) = @_;
    $method ||= 'GET';
    my $browser = LWP::UserAgent->new();
    my $url = url($endpoint.$path);
    $url->query_form(%params);
    my $request = HTTP::Request->new($method => $url);
    $request->header('X-Auth-Token'=>$token);
    my $response = $browser->request($request);
    unless($response->is_success){
        return {error=>"fetch error: ".$response->status_line};
    }
    my $resp= eval {JSON::XS::decode_json($response->content)};
    return $@ ? {error=>"packet format: $@"} : $resp;
}

sub makedns_usage
{
    my $callback = shift;

    my $rsp;
    push @{$rsp->{data}},
      "\n  makedns - sets up domain name services (DNS) for Nova DNS.";
    push @{$rsp->{data}}, "  Usage: ";
    push @{$rsp->{data}}, "\tmakedns [-h|--help ]";
    push @{$rsp->{data}}, "\tmakedns [-n|--new ] noderange";
    push @{$rsp->{data}}, "\tmakedns [-d|--delete noderange]";
    push @{$rsp->{data}}, "\n";
    xCAT::MsgUtils->message("I", $rsp, $callback);
    return 0;
}


1;
