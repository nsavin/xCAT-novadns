Summary:    Nova-DNS plugin for xCAT 
Name:	    xCAT-novadns
Version:    %(cat Version)
Release:    1 
Group:	    Applications/System
Source0:    %{name}-%{version}.tar.gz
BuildRoot:  %{_tmppath}/%{name}-%{version}-build
BuildArch:  noarch
Prefix:	    /opt/xcat
Requires:   xCAT-server >= 2.6
Requires:   xCAT-client >= 2.6

%description
xCAT-novadns contains plugins for use `makedns` command with Nova DNS API.

%prep
%setup -q -n xCAT-novadns
%build
%install
rm -rf $RPM_BUILD_ROOT
mkdir -p ${RPM_BUILD_ROOT}%{prefix}/lib/perl/xCAT_plugin
set +x
cp opt/xcat/lib/perl/xCAT_plugin/* $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin
chmod 644 $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/*

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root)
%{prefix}

%changelog
* Fri Feb 24 17:16:25 EET 2012 - Savin Nikita  <nsavin@griddynamics.com>
- initial SPEC file

%post
if [ -f "/proc/cmdline" ]
then
	echo "Restarting xCAT for plugins to take effect..."
	/etc/init.d/xcat reload
fi
