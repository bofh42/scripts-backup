
Summary:       Nagios check for borg and restic backup scripts
Name:          nagios-plugins-backup
Version:       2.2.0
Release:       1%{?dist}
Group:         42/extras
License:       GPLv2+
Obsoletes:     nagios-plugins-borgbackup < 2.0
Provides:      nagios-plugins-borgbackup

Source0:       _check_backup.sh
Source1:       https://www.gnu.org/licenses/gpl-2.0.txt
Source2:       plugin-backup.cfg.in

BuildArch:     noarch
BuildRequires: sed
BuildRoot:     %{_tmppath}/%{name}-%{version}-root

%description
Nagios check for borg and restic backup scripts and freshness of backups.

%prep
%{__install} -d %{_builddir}/%{name}-%{version}

%install
[ "%{buildroot}" != "/" ] && %{__rm} -rf %{buildroot}

# license
cp %{SOURCE1} .

# create directories
%{__install} -d %{buildroot}%{_libdir}/nagios/plugins/
%{__install} -d %{buildroot}%{_sysconfdir}/nagios/nrpe.d/

# install plugin
%{__install} -c -m 755 %{SOURCE0} %{buildroot}%{_libdir}/nagios/plugins/_check_backup.sh
%{__ln_s} _check_backup.sh %{buildroot}%{_libdir}/nagios/plugins/check_borgbackup.sh
%{__ln_s} _check_backup.sh %{buildroot}%{_libdir}/nagios/plugins/check_resticbackup.sh
%{__ln_s} _check_backup.sh %{buildroot}%{_libdir}/nagios/plugins/check_otherbackup.sh

# install nrpe config
%{__install} -Dp -m0644 %{SOURCE2} %{buildroot}%{_sysconfdir}/nagios/nrpe.d/plugin-backup.cfg
%{__sed} -i -e "s|__libexecdir__|%{_libdir}/nagios/plugins|g" %{buildroot}%{_sysconfdir}/nagios/nrpe.d/plugin-backup.cfg


%clean
[ "%{buildroot}" != "/" ] && %{__rm} -rf %{buildroot}

%post
service nrpe reload >/dev/null 2>&1 || :

%postun
service nrpe reload >/dev/null 2>&1 || :


%files
%license gpl-2.0.txt
%defattr(-,root,root)
%{_libdir}/nagios/plugins/*.sh
%{_sysconfdir}/nagios/nrpe.d/plugin-backup.cfg

%changelog
* Tue Aug 04 2026 Peter Tuschy <foss+rpm@bofh42.de> - 2.2.0-1
- added lock detection for restic

* Wed Apr 22 2026 Peter Tuschy <foss+rpm@bofh42.de> - 2.1.0-1
- added type other
- default war 15 -> 10

* Tue Apr 07 2026 Peter Tuschy <foss+rpm@bofh42.de> - 2.0.0-1
- initial unified check for borg an restic
