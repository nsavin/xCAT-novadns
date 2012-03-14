Summary:    Nova-DNS plugin for xCAT 
Name:	    xCAT-novadns
Version:    0.0.1 
Release:    1 
License:    GNU LGPL v2.1
Vendor:     Grid Dynamics International, Inc.
URL:        http://www.griddynamics.com/openstack
Group:	    Applications/System
Source0:    %{name}-%{version}.tar.gz
BuildRoot:  %{_tmppath}/%{name}-%{version}-build
BuildArch:  noarch
Requires:   perl-JSON-XS
AutoReqProv: no

%description
xCAT-novadns contains plugins for use `makedns` command with Nova DNS API.


%prep
%setup -q -n %{name}-%{version}
%build
%install
%__rm -rf %{buildroot}
mkdir -p %{buildroot}/opt/xcat/lib/perl/xCAT_plugin
set +x
cp xCAT-novadns/opt/xcat/lib/perl/xCAT_plugin/* %{buildroot}/opt/xcat/lib/perl/xCAT_plugin
chmod 644 %{buildroot}/opt/xcat/lib/perl/xCAT_plugin/*

%clean
%__rm -rf %{buildroot}

%files
%defattr(-,root,root)
/opt/xcat

%changelog
* Mon Feb 27 2012 Savin Nikita  <nsavin@griddynamics.com>
- remove xCAT requires (to make happy build server)
- add perl-JSON-XS requires
* Fri Feb 24 2012 Savin Nikita  <nsavin@griddynamics.com>
- initial SPEC file

%post
if [ -f "/proc/cmdline" ]
then
	echo "Restarting xCAT for plugins to take effect..."
	/etc/init.d/xcat reload
fi
