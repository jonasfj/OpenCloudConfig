function Write-Log {
  param (
    [string] $message,
    [string] $severity = 'INFO',
    [string] $source = 'OpenCloudConfig',
    [string] $logName = 'Application'
  )
  if (!([Diagnostics.EventLog]::Exists($logName)) -or !([Diagnostics.EventLog]::SourceExists($source))) {
    New-EventLog -LogName $logName -Source $source
  }
  switch ($severity) {
    'DEBUG' {
      $entryType = 'SuccessAudit'
      $eventId = 2
      break
    }
    'WARN' {
      $entryType = 'Warning'
      $eventId = 3
      break
    }
    'ERROR' {
      $entryType = 'Error'
      $eventId = 4
      break
    }
    default {
      $entryType = 'Information'
      $eventId = 1
      break
    }
  }
  Write-EventLog -LogName $logName -Source $source -EntryType $entryType -Category 0 -EventID $eventId -Message $message
}
function Run-RemoteDesiredStateConfig {
  param (
    [string] $url
  )
  Stop-DesiredStateConfig
  $config = [IO.Path]::GetFileNameWithoutExtension($url)
  $target = ('{0}\{1}.ps1' -f $env:Temp, $config)
  Remove-Item $target -confirm:$false -force -ErrorAction SilentlyContinue
  (New-Object Net.WebClient).DownloadFile(('{0}?{1}' -f $url, [Guid]::NewGuid()), $target)
  Write-Log -message ('{0} :: downloaded {1}, from {2}.' -f $($MyInvocation.MyCommand.Name), $target, $url) -severity 'DEBUG'
  Unblock-File -Path $target
  . $target
  $mof = ('{0}\{1}' -f $env:Temp, $config)
  Remove-Item $mof -confirm:$false -recurse:$true -force -ErrorAction SilentlyContinue
  Invoke-Expression "$config -OutputPath $mof"
  Write-Log -message ('{0} :: compiled mof {1}, from {2}.' -f $($MyInvocation.MyCommand.Name), $mof, $config) -severity 'DEBUG'
  Start-DscConfiguration -Path "$mof" -Wait -Verbose -Force
}
function Stop-DesiredStateConfig {
  # terminate any running dsc process
  $dscpid = (Get-WmiObject msft_providers | ? {$_.provider -like 'dsccore'} | Select-Object -ExpandProperty HostProcessIdentifier)
  if ($dscpid) {
    Get-Process -Id $dscpid | Stop-Process -f
    Write-Log -message ('{0} :: dsc process with pid {1}, stopped.' -f $($MyInvocation.MyCommand.Name), $dscpid) -severity 'DEBUG'
  }
}
function Remove-DesiredStateConfigTriggers {
  try {
    $scheduledTask = 'RunDesiredStateConfigurationAtStartup'
    Start-Process 'schtasks.exe' -ArgumentList @('/Delete', '/tn', $scheduledTask, '/F') -Wait -NoNewWindow -PassThru -RedirectStandardOutput ('{0}\log\{1}.schtask-{2}-delete.stdout.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"), $scheduledTask) -RedirectStandardError ('{0}\log\{1}.schtask-{2}-delete.stderr.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"), $scheduledTask)
    Write-Log -message 'scheduled task: RunDesiredStateConfigurationAtStartup, deleted.' -severity 'INFO'
  }
  catch {
    Write-Log -message ('failed to delete scheduled task: {0}. {1}' -f $scheduledTask, $_.Exception.Message) -severity 'ERROR'
  }
  foreach ($mof in @('Previous', 'backup', 'Current')) {
    if (Test-Path -Path ('{0}\System32\Configuration\{1}.mof' -f $env:SystemRoot, $mof) -ErrorAction SilentlyContinue) {
      Remove-Item -Path ('{0}\System32\Configuration\{1}.mof' -f $env:SystemRoot, $mof) -confirm:$false -force
      Write-Log -message ('{0}\System32\Configuration\{1}.mof deleted' -f $env:SystemRoot, $mof) -severity 'INFO'
    }
  }
  Remove-Item -Path 'C:\dsc\rundsc.ps1' -confirm:$false -force
  Write-Log -message 'C:\dsc\rundsc.ps1 deleted' -severity 'INFO'
}
function Remove-LegacyStuff {
  param (
    [string] $logFile,
    [string[]] $users = @(
      'cltbld',
      'GenericWorker'
    ),
    [string[]] $paths = @(
      ('{0}\default_browser' -f $env:SystemDrive),
      ('{0}\etc' -f $env:SystemDrive),
      ('{0}\generic-worker' -f $env:SystemDrive),
      ('{0}\gpo_files' -f $env:SystemDrive),
      ('{0}\installersource' -f $env:SystemDrive),
      ('{0}\installservice.bat' -f $env:SystemDrive),
      ('{0}\log\*.zip' -f $env:SystemDrive),
      ('{0}\mozilla-build-bak' -f $env:SystemDrive),
      ('{0}\mozilla-buildbuildbotve' -f $env:SystemDrive),
      ('{0}\mozilla-buildpython27' -f $env:SystemDrive),
      ('{0}\nxlog\conf\nxlog_*.conf' -f $env:ProgramFiles),
      ('{0}\opt' -f $env:SystemDrive),
      ('{0}\opt.zip' -f $env:SystemDrive),
      ('{0}\Puppet Labs' -f $env:ProgramFiles),
      ('{0}\PuppetLabs' -f $env:ProgramData),
      ('{0}\puppetagain' -f $env:ProgramData),
      ('{0}\quickedit' -f $env:SystemDrive),
      ('{0}\slave' -f $env:SystemDrive),
      ('{0}\sys-scripts' -f $env:SystemDrive),
      ('{0}\System32\Configuration\backup.mof' -f $env:SystemRoot),
      ('{0}\System32\Configuration\Current.mof' -f $env:SystemRoot),
      ('{0}\System32\Configuration\Previous.mof' -f $env:SystemRoot),
      ('{0}\System32\Tasks\runner' -f $env:SystemRoot),
      ('{0}\timeset.bat' -f $env:SystemDrive),
      ('{0}\updateservice' -f $env:SystemDrive),
      ('{0}\Users\Administrator\Desktop\TESTER RUNNER' -f $env:SystemDrive),
      ('{0}\Users\Administrator\Desktop\PyYAML-3.11' -f $env:SystemDrive),
      ('{0}\Users\Administrator\Desktop\PyYAML-3.11.zip' -f $env:SystemDrive),
      ('{0}\Users\Public\Desktop\*.lnk' -f $env:SystemDrive),
      ('{0}\Users\root\Desktop\*.reg' -f $env:SystemDrive)
    ),
    [string[]] $services = @(
      'puppet',
      'uvnc_service'
    ),
    [string[]] $scheduledTasks = @(
      'Disable_maintain',
      'Disable_Notifications',
      '"INSTALL on startup"',
      'rm_reboot_semaphore',
      'RunDesiredStateConfigurationAtStartup',
      '"START RUNNER"',
      'Update_Logon_Count.xml',
      'enabel-userdata-execution',
      '"Make sure userdata runs"',
      '"Run Generic Worker on login"',
      'timesync',
      'runner'
    ),
    [string[]] $registryKeys = @(
      'HKLM:\SOFTWARE\PuppetLabs'
    ),
    [hashtable] $registryEntries = @{
      # g-w won't set autologin password if these keys pre-exist
      # https://github.com/taskcluster/generic-worker/blob/fb74177141c39afaa1daae53b6fb2a01edd8f32d/plat_windows.go#L440
      'DefaultUserName' = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon';
      'DefaultPassword' = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon';
      'AutoAdminLogon' = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    },
    [hashtable] $ec2ConfigSettings = @{
      'Ec2HandleUserData' = 'Enabled';
      'Ec2InitializeDrives' = 'Enabled';
      'Ec2EventLog' = 'Enabled';
      'Ec2OutputRDPCert' = 'Enabled';
      'Ec2SetDriveLetter' = 'Enabled';
      'Ec2WindowsActivate' = 'Enabled';
      'Ec2SetPassword' = 'Disabled';
      'Ec2SetComputerName' = 'Disabled';
      'Ec2ConfigureRDP' = 'Disabled';
      'Ec2DynamicBootVolumeSize' = 'Disabled';
      'AWS.EC2.Windows.CloudWatch.PlugIn' = 'Disabled'
    }
  )

  # clear the event log
  wevtutil el | % { wevtutil cl $_ }

  # remove scheduled tasks
  foreach ($scheduledTask in $scheduledTasks) {
    try {
      Start-Process 'schtasks.exe' -ArgumentList @('/Delete', '/tn', $scheduledTask, '/F') -Wait -NoNewWindow -PassThru -RedirectStandardOutput ('{0}\log\{1}.schtask-{2}-delete.stdout.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"), $scheduledTask) -RedirectStandardError ('{0}\log\{1}.schtask-{2}-delete.stderr.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"), $scheduledTask)
      Write-Log -message ('{0} :: scheduled task: {1}, deleted.' -f $($MyInvocation.MyCommand.Name), $scheduledTask) -severity 'INFO'
    }
    catch {
      Write-Log -message ('{0} :: failed to delete scheduled task: {1}. {2}' -f $($MyInvocation.MyCommand.Name), $scheduledTask, $_.Exception.Message) -severity 'ERROR'
    }
  }

  # remove user accounts
  foreach ($user in $users) {
    if (@(Get-WMiObject -class Win32_UserAccount | Where { $_.Name -eq $user }).length -gt 0) {
      Start-Process 'logoff' -ArgumentList @((((quser /server:. | ? { $_ -match $user }) -split ' +')[2]), '/server:.') -Wait -NoNewWindow -PassThru -RedirectStandardOutput ('{0}\log\{1}.net-user-{2}-logoff.stdout.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"), $user) -RedirectStandardError ('{0}\log\{1}.net-user-{2}-logoff.stderr.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"), $user)
      Start-Process 'net' -ArgumentList @('user', $user, '/DELETE') -Wait -NoNewWindow -PassThru -RedirectStandardOutput ('{0}\log\{1}.net-user-{2}-delete.stdout.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"), $user) -RedirectStandardError ('{0}\log\{1}.net-user-{2}-delete.stderr.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"), $user)
      Write-Log -message ('{0} :: user: {1}, deleted.' -f $($MyInvocation.MyCommand.Name), $user) -severity 'INFO'
    }
    if (Test-Path -Path ('{0}\Users\{1}' -f $env:SystemDrive, $user) -ErrorAction SilentlyContinue) {
      Remove-Item ('{0}\Users\{1}' -f $env:SystemDrive, $user) -confirm:$false -recurse:$true -force -ErrorAction SilentlyContinue
      Write-Log -message ('{0} :: path: {1}, deleted.' -f $($MyInvocation.MyCommand.Name), ('{0}\Users\{1}' -f $env:SystemDrive, $user)) -severity 'INFO'
    }
    if (Test-Path -Path ('{0}\Users\{1}*' -f $env:SystemDrive, $user) -ErrorAction SilentlyContinue) {
      Remove-Item ('{0}\Users\{1}*' -f $env:SystemDrive, $user) -confirm:$false -recurse:$true -force -ErrorAction SilentlyContinue
      Write-Log -message ('{0} :: path: {1}, deleted.' -f $($MyInvocation.MyCommand.Name), ('{0}\Users\{1}*' -f $env:SystemDrive, $user)) -severity 'INFO'
    }
  }

  # delete paths
  foreach ($path in $paths) {
    if (Test-Path -Path $path -ErrorAction SilentlyContinue) {
      Remove-Item $path -confirm:$false -recurse:$true -force -ErrorAction SilentlyContinue
      Write-Log -message ('{0} :: path: {1}, deleted.' -f $($MyInvocation.MyCommand.Name), $path) -severity 'INFO'
    }
  }

  # delete old mozilla-build. presence of python27 indicates old mozilla-build
  if (Test-Path -Path ('{0}\mozilla-build\python27' -f $env:SystemDrive) -ErrorAction SilentlyContinue) {
    Remove-Item ('{0}\mozilla-build' -f $env:SystemDrive) -confirm:$false -recurse:$true -force -ErrorAction SilentlyContinue
    Write-Log -message ('{0} :: path: {1}, deleted.' -f $($MyInvocation.MyCommand.Name), ('{0}\mozilla-build' -f $env:SystemDrive)) -severity 'INFO'
  }

  # delete services
  foreach ($service in $services) {
    if (Get-Service -Name $service -ErrorAction SilentlyContinue) {
      Get-Service -Name $service | Stop-Service -PassThru
      (Get-WmiObject -Class Win32_Service -Filter "Name='$service'").delete()
      Write-Log -message ('{0} :: service: {1}, deleted.' -f $($MyInvocation.MyCommand.Name), $service) -severity 'INFO'
    }
  }

  # remove registry keys
  foreach ($registryKey in $registryKeys) {
    if ((Get-Item -Path $registryKey -ErrorAction SilentlyContinue) -ne $null) {
      Remove-Item -Path $registryKey -recurse
      Write-Log -message ('{0} :: registry key: {1}, deleted.' -f $($MyInvocation.MyCommand.Name), $registryKey) -severity 'INFO'
    }
  }

  # remove registry entries
  foreach ($name in $registryEntries.Keys) {
    $path = $registryEntries.Item($name)
    $item = (Get-Item -Path $path)
    if (($item -ne $null) -and ($item.GetValue($name) -ne $null)) {
      Remove-ItemProperty -path $path -name $name
      Write-Log -message ('{0} :: registry entry: {1}\{2}, deleted.' -f $($MyInvocation.MyCommand.Name), $path, $name) -severity 'INFO'
    }
  }

  # reset ec2 config settings
  $ec2ConfigSettingsFile = 'C:\Program Files\Amazon\Ec2ConfigService\Settings\Config.xml'
  $ec2ConfigSettingsFileModified = $false;
  [xml]$xml = (Get-Content $ec2ConfigSettingsFile)
  foreach ($plugin in $xml.DocumentElement.Plugins.Plugin) {
    if ($ec2ConfigSettings.ContainsKey($plugin.Name)) {
      if ($plugin.State -ne $ec2ConfigSettings[$plugin.Name]) {
        $plugin.State = $ec2ConfigSettings[$plugin.Name]
        $ec2ConfigSettingsFileModified = $true
        Write-Log -message ('{0} :: Ec2Config {1} set to: {2}, in: {3}' -f $($MyInvocation.MyCommand.Name), $plugin.Name, $plugin.State, $ec2ConfigSettingsFile) -severity 'INFO'
      }
    }
  }
  if ($ec2ConfigSettingsFileModified) {
    & 'icacls' @($ec2ConfigSettingsFile, '/grant', 'Administrators:F') | Out-File -filePath $logFile -append
    & 'icacls' @($ec2ConfigSettingsFile, '/grant', 'System:F') | Out-File -filePath $logFile -append
    $xml.Save($ec2ConfigSettingsFile) | Out-File -filePath $logFile -append
  }
}
function Map-DriveLetters {
  param (
    [hashtable] $driveLetterMap = @{
      'D:' = 'Y:';
      'E:' = 'Z:'
    }
  )
  $driveLetterMap.Keys | % {
    $old = $_
    $new = $driveLetterMap.Item($_)
    if (Test-Path -Path ('{0}\' -f $old) -ErrorAction SilentlyContinue) {
      $volume = Get-WmiObject -Class win32_volume -Filter "DriveLetter='$old'"
      if ($null -ne $volume) {
        $volume.DriveLetter = $new
        $volume.Put()
        Write-Log -message ('{0} :: drive {1} assigned new drive letter: {2}.' -f $($MyInvocation.MyCommand.Name), $old, $new) -severity 'INFO'
      }
    }
  }
  if ((Test-Path -Path 'Y:\' -ErrorAction SilentlyContinue) -and (-not (Test-Path -Path 'Z:\' -ErrorAction SilentlyContinue))) {
    $volume = Get-WmiObject -Class win32_volume -Filter "DriveLetter='Y:'"
    if ($null -ne $volume) {
      $volume.DriveLetter = 'Z:'
      $volume.Put()
      Write-Log -message ('{0} :: drive Y: assigned new drive letter: Z:.' -f $($MyInvocation.MyCommand.Name)) -severity 'INFO'
    }
  }
}
function Set-Credentials {
  param (
    [string] $username,
    [string] $password,
    [switch] $setautologon
  )
  try {
    & net @('user', $username, $password)
    Write-Log -message ('{0} :: credentials set for user: {1}.' -f $($MyInvocation.MyCommand.Name), $username) -severity 'INFO'
    if ($setautologon) {
      Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Type 'String' -Name 'DefaultPassword' -Value $password
      Write-Log -message ('{0} :: autologon set for user: {1}.' -f $($MyInvocation.MyCommand.Name), $username) -severity 'INFO'
    }
  }
  catch {
    Write-Log -message ('{0} :: failed to set credentials for user: {1}. {2}' -f $($MyInvocation.MyCommand.Name), $username, $_.Exception.Message) -severity 'ERROR'
  }
}
function Run-Dsc32BitBypass {
  # nxlog
  (New-Object Net.WebClient).DownloadFile('http://nxlog.co/system/files/products/files/1/nxlog-ce-2.9.1716.msi', 'Z:\nxlog-ce-2.9.1716.msi')
  Start-Process msiexec.exe -ArgumentList @('/package', 'Z:\nxlog-ce-2.9.1716.msi', '/quiet', '/norestart', '/log', ('C:\log\{0}-nxlog-ce-2.9.1716.msi.install.log' -f [DateTime]::Now.ToString("yyyyMMddHHmmss"))) -wait
  (New-Object Net.WebClient).DownloadFile('https://papertrailapp.com/tools/papertrail-bundle.pem', 'C:\Program Files\nxlog\cert\papertrail-bundle.pem')

  $registryKeys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps'
  )
  $registryEntries = @(

    # Puppet Legacy (process_priority)
    New-Object PSObject -Property @{Path='HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl';Type='DWord';Value=0x00000026;Name='Win32PrioritySeparation'},

    # Puppet Legacy (ntfs_options)
    New-Object PSObject -Property @{Path='HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps';Type='DWord';Value=0x00000001;Name='DumpType'},
    New-Object PSObject -Property @{Path='HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem';Type='DWord';Value=0x00000001;Name='NtfsDisable8dot3NameCreation'},
    New-Object PSObject -Property @{Path='HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem';Type='DWord';Value=0x00000001;Name='NtfsDisableLastAccessUpdate'},
    New-Object PSObject -Property @{Path='HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem';Type='DWord';Value=0x00000002;Name='NtfsMemoryUsage'},

    # Puppet Legacy (memory_paging)
    New-Object PSObject -Property @{Path='HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management';Type='DWord';Value=0x00000001;Name='DisablePagingExecutive'},
    New-Object PSObject -Property @{Path='HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters';Type='DWord';Value=0x00000012;Name='BootId'},
    New-Object PSObject -Property @{Path='HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters';Type='DWord';Value=0x185729f9;Name='BaseTime'},

    # Puppet Legacy (windows_network_opt_registry)
    New-Object PSObject -Property @{Path='HKLM:\SYSTEM\CurrentControlSet\services\Tcpip\ServiceProvider';Type='DWord';Value=0x00002000;Name='DnsPriority'},
    New-Object PSObject -Property @{Path='HKLM:\SYSTEM\CurrentControlSet\services\Tcpip\ServiceProvider';Type='DWord';Value=0x00000500;Name='HostsPriority'},
    New-Object PSObject -Property @{Path='HKLM:\SYSTEM\CurrentControlSet\services\Tcpip\ServiceProvider';Type='DWord';Value=0x00000499;Name='LocalPriority'},
    New-Object PSObject -Property @{Path='HKLM:\SYSTEM\CurrentControlSet\services\Tcpip\ServiceProvider';Type='DWord';Value=0x00002001;Name='NetbtPriority'},
    New-Object PSObject -Property @{Path='HKLM:\SYSTEM\CurrentControlSet\services\LanmanServer\Parameters';Type='DWord';Value=0x00000003;Name='Size'},
    New-Object PSObject -Property @{Path='HKLM:\SYSTEM\CurrentControlSet\services\LanmanServer\Parameters';Type='DWord';Value=0x00000003;Name='AdjustedNullSessionPipes'},
    New-Object PSObject -Property @{Path='HKLM:\SYSTEM\CurrentControlSet\services\AFD\Parameters';Type='DWord';Value=0x05316608;Name='DefaultSendWindow'},
    New-Object PSObject -Property @{Path='HKLM:\SYSTEM\CurrentControlSet\services\AFD\Parameters';Type='DWord';Value=0x05316608;Name='DefaultReceiveWindow'},
    New-Object PSObject -Property @{Path='HKLM:\SYSTEM\CurrentControlSet\services\Tcpip\Parameters';Type='DWord';Value=0x00000003;Name='Tcp1323Opts'},
    New-Object PSObject -Property @{Path='HKLM:\SYSTEM\CurrentControlSet\services\Tcpip\Parameters';Type='DWord';Value=0x00000005;Name='TCPMaxDataRetransmissions'},
    New-Object PSObject -Property @{Path='HKLM:\SYSTEM\CurrentControlSet\services\Tcpip\Parameters';Type='DWord';Value=0x00000000;Name='SynAttackProtect_SEL'},
    New-Object PSObject -Property @{Path='HKLM:\SYSTEM\CurrentControlSet\services\Tcpip\Parameters';Type='DWord';Value=0x00000001;Name='DisableTaskOffload'},
    New-Object PSObject -Property @{Path='HKLM:\SYSTEM\CurrentControlSet\services\Tcpip\Parameters';Type='DWord';Value=0x00000001;Name='DisableTaskOffload_SEL'},
    New-Object PSObject -Property @{Path='HKLM:\SYSTEM\CurrentControlSet\services\Tcpip\Parameters';Type='DWord';Value=0x00000040;Name='DefaultTTL'},
    New-Object PSObject -Property @{Path='HKLM:\SYSTEM\CurrentControlSet\services\Tcpip\Parameters';Type='DWord';Value=0x00000030;Name='TcpTimedWaitDelay'},
    New-Object PSObject -Property @{Path='HKLM:\SOFTWARE\Microsoft\Internet Explorer\MAIN\FeatureControl\FEATURE_MAXCONNECTIONSPER1_0SERVER';Type='DWord';Value=0x00000016;Name='explorer.exe'},
    New-Object PSObject -Property @{Path='HKLM:\SOFTWARE\Microsoft\Internet Explorer\MAIN\FeatureControl\FEATURE_MAXCONNECTIONSPER1_0SERVER';Type='DWord';Value=0x00000016;Name='iexplorer.exe'},
    New-Object PSObject -Property @{Path='HKLM:\SOFTWARE\Microsoft\Internet Explorer\MAIN\FeatureControl\FEATURE_MAXCONNECTIONSPERSERVER';Type='DWord';Value=0x00000016;Name='explorer.exe_01'},
    New-Object PSObject -Property @{Path='HKLM:\SOFTWARE\Microsoft\Internet Explorer\MAIN\FeatureControl\FEATURE_MAXCONNECTIONSPERSERVER';Type='DWord';Value=0x00000016;Name='iexplorer.exe_01'},
    New-Object PSObject -Property @{Path='HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management';Type='DWord';Value=0x00000001;Name='LargeSystemCache'},
    New-Object PSObject -Property @{Path='HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters';Type='DWord';Value=0x00000000;Name='NegativeCacheTime'},
    New-Object PSObject -Property @{Path='HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters';Type='DWord';Value=0x00000000;Name='NetFailureCacheTime'},
    New-Object PSObject -Property @{Path='HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters';Type='DWord';Value=0x00000000;Name='NegativeSOACacheTime'},
    New-Object PSObject -Property @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched';Type='DWord';Value=0x00000000;Name='NonBestEffortLimit'},
    New-Object PSObject -Property @{Path='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile';Type='DWord';Value=0x4294967295;Name='NetworkThrottlingIndex'},
    New-Object PSObject -Property @{Path='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile';Type='DWord';Value=0x00000010;Name='SystemResponsiveness'},
    New-Object PSObject -Property @{Path='HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters';Type='DWord';Value=0x4294967295;Name='DisabledComponents'},
    New-Object PSObject -Property @{Path='HKLM:\SOFTWARE\Microsoft\MSMQ\Parameters';Type='DWord';Value=0x00000001;Name='LargeSystemCache_SEL'}
  )
  
  foreach ($rk in $registryKeys) {
    New-Item $rk -ErrorAction SilentlyContinue
    Write-Log -message ('{0} :: registry key {1} created.' -f $($MyInvocation.MyCommand.Name), $rk) -severity 'INFO'
  }
  foreach ($re in $registryEntries) {
    Set-ItemProperty -Path $re.Path -Type $re.Type -Name $re.Name -Value $re.Value
    Write-Log -message ('{0} :: registry entry {1}\{2} set to {3} {4}.' -f $($MyInvocation.MyCommand.Name), $re.Path, $re.Name, $re.Type, $re.Value) -severity 'INFO'
  }

  # generic worker
  $gwVersion = '6.1.0'
  New-Item -Path 'C:\generic-worker' -ItemType directory -force
  (New-Object Net.WebClient).DownloadFile(('https://github.com/taskcluster/generic-worker/releases/download/v{0}/generic-worker-windows-386.exe' -f $gwVersion), 'C:\generic-worker\generic-worker.exe')
  (New-Object Net.WebClient).DownloadFile('https://github.com/taskcluster/livelog/releases/download/v1.0.0/livelog-windows-386.exe', 'C:\generic-worker\livelog.exe')
  & 'C:\generic-worker\generic-worker.exe' @('install', 'startup', '--config', 'C:\generic-worker\generic-worker.config')
  (New-Object Net.WebClient).DownloadFile('https://raw.githubusercontent.com/mozilla-releng/OpenCloudConfig/master/userdata/Configuration/GenericWorker/run-generic-worker.bat', 'C:\generic-worker\run-generic-worker.bat')
  if ((& 'netsh.exe' @('advfirewall', 'firewall', 'show', 'rule', 'name=LiveLog_Get')) -contains 'No rules match the specified criteria.') {
    & 'netsh.exe' @('advfirewall', 'firewall', 'add', 'rule', 'name=LiveLog_Get', 'dir=in', 'action=allow', 'protocol=TCP', 'localport=60022')
  }
  if ((& 'netsh.exe' @('advfirewall', 'firewall', 'show', 'rule', 'name=LiveLog_Put')) -contains 'No rules match the specified criteria.') {
    & 'netsh.exe' @('advfirewall', 'firewall', 'add', 'rule', 'name=LiveLog_Put', 'dir=in', 'action=allow', 'protocol=TCP', 'localport=60023')
  }
  Write-Log -message ('{0} :: generic-worker and livelog downloaded, installed and configured.' -f $($MyInvocation.MyCommand.Name)) -severity 'INFO'

  # mercurial
  (New-Object Net.WebClient).DownloadFile('https://www.mercurial-scm.org/release/windows/Mercurial-3.9.1.exe', 'Z:\Mercurial-3.9.1.exe')
  & 'Z:\Mercurial-3.9.1.exe' @('/SP-', '/VERYSILENT', '/NORESTART', '/DIR=expand:{pf}\Mercurial', '/LOG="C:\log\Mercurial-3.9.1.exe.install.log"')
  (New-Object Net.WebClient).DownloadFile('https://raw.githubusercontent.com/mozilla-releng/OpenCloudConfig/master/userdata/Configuration/Mercurial/mercurial.ini', 'C:\Program Files\Mercurial\Mercurial.ini')
  (New-Object Net.WebClient).DownloadFile('https://raw.githubusercontent.com/mozilla-releng/OpenCloudConfig/master/userdata/Configuration/Mercurial/cacert.pem', 'C:\mozilla-build\msys\etc\cacert.pem')
  Write-Log -message ('{0} :: hg 3.9.1 downloaded, installed and configured.' -f $($MyInvocation.MyCommand.Name)) -severity 'INFO'

  # mozilla-build
  (New-Object Net.WebClient).DownloadFile('http://ftp.mozilla.org/pub/mozilla/libraries/win32/MozillaBuildSetup-2.2.0.exe', 'Z:\MozillaBuildSetup-2.2.0.exe')
  Write-Log -message ('{0} :: mozilla-build 2.2.0 downloaded.' -f $($MyInvocation.MyCommand.Name)) -severity 'INFO'
  & 'Z:\MozillaBuildSetup-2.2.0.exe' @('/S', '/D=C:\mozilla-build')
  Write-Log -message ('{0} :: mozilla-build 2.2.0 installed.' -f $($MyInvocation.MyCommand.Name)) -severity 'INFO'

  # tooltool
  (New-Object Net.WebClient).DownloadFile('https://raw.githubusercontent.com/mozilla/build-tooltool/master/tooltool.py', 'C:\mozilla-build\tooltool.py')
  Write-Log -message ('{0} :: tooltool downloaded.' -f $($MyInvocation.MyCommand.Name)) -severity 'INFO'
  
  # virtualenv
  (New-Object Net.WebClient).DownloadFile('https://hg.mozilla.org/mozilla-central/raw-file/8c9eed5227f8/python/virtualenv/virtualenv.py', 'C:\mozilla-build\python\Lib\site-packages\virtualenv.py')
  Write-Log -message ('{0} :: virtualenv downloaded.' -f $($MyInvocation.MyCommand.Name)) -severity 'INFO'
  $wheels = @(
    'argparse-1.4.0-py2.py3-none-any.whl',
    'pip-8.1.2-py2.py3-none-any.whl',
    'setuptools-25.2.0-py2.py3-none-any.whl',
    'wheel-0.29.0-py2.py3-none-any.whl'
  )
  foreach ($wheel in $wheels) {
    if (-not (Test-Path -Path ('C:\mozilla-build\python\Lib\site-packages\virtualenv_support\{0}' -f $wheel) -ErrorAction SilentlyContinue)) {
      (New-Object Net.WebClient).DownloadFile(('https://hg.mozilla.org/mozilla-central/raw-file/8c9eed5227f8/python/virtualenv/virtualenv_support/{0}' -f $wheel), ('C:\mozilla-build\python\Lib\site-packages\virtualenv_support\{0}' -f $wheel))
      Write-Log -message ('{0} :: {1} downloaded.' -f $($MyInvocation.MyCommand.Name), $wheel) -severity 'INFO'
    }
  }

  # robustcheckout
  (New-Object Net.WebClient).DownloadFile('https://raw.githubusercontent.com/mozilla-releng/OpenCloudConfig/master/userdata/Configuration/FirefoxBuildResources/robustcheckout.py', 'C:\mozilla-build\robustcheckout.py')
  Write-Log -message ('{0} :: robustcheckout downloaded.' -f $($MyInvocation.MyCommand.Name)) -severity 'INFO'

  # pip conf
  New-Item -Path 'C:\ProgramData\pip' -ItemType directory -force
  (New-Object Net.WebClient).DownloadFile('https://raw.githubusercontent.com/mozilla-releng/OpenCloudConfig/master/userdata/Configuration/pip.conf', 'C:\ProgramData\pip\pip.ini')
  Write-Log -message ('{0} :: pip config installed.' -f $($MyInvocation.MyCommand.Name)) -severity 'INFO'

  # PythonPath registry
  Set-ItemProperty 'HKLM:\SOFTWARE\Python\PythonCore\2.7\InstallPath' -Type 'String' -Name '(Default)' -Value 'C:\mozilla-build\python\'
  Set-ItemProperty 'HKLM:\SOFTWARE\Python\PythonCore\2.7\PythonPath' -Type 'String' -Name '(Default)' -Value 'C:\mozilla-build\python\Lib;C:\mozilla-build\python\DLLs;C:\mozilla-build\python\Lib\lib-tk'
  Write-Log -message ('{0} :: PythonPath registry value set.' -f $($MyInvocation.MyCommand.Name)) -severity 'INFO'

  $pathPrepend = @(
    'C:\Program Files\Mercurial',
    'C:\mozilla-build\7zip',
    'C:\mozilla-build\info-zip',
    'C:\mozilla-build\kdiff3',
    'C:\mozilla-build\moztools-x64\bin',
    'C:\mozilla-build\mozmake',
    'C:\mozilla-build\msys\bin',
    'C:\mozilla-build\msys\local\bin',
    'C:\mozilla-build\nsis-3.0b3',
    'C:\mozilla-build\nsis-2.46u',
    'C:\mozilla-build\python',
    'C:\mozilla-build\python\Scripts',
    'C:\mozilla-build\upx391w',
    'C:\mozilla-build\wget',
    'C:\mozilla-build\yasm'
  )
  $env:PATH = (@(($pathPrepend + @($env:PATH -split ';')) | select -Unique) -join ';')
  [Environment]::SetEnvironmentVariable('PATH', $env:Path, 'Machine')
  Write-Log -message ('{0} :: environment PATH set ({1}).' -f $($MyInvocation.MyCommand.Name), $env:PATH) -severity 'INFO'

  $env:MOZILLABUILD = 'C:\mozilla-build'
  [Environment]::SetEnvironmentVariable('MOZILLABUILD', $env:MOZILLABUILD, 'Machine')
  Write-Log -message ('{0} :: environment MOZILLABUILD set ({1}).' -f $($MyInvocation.MyCommand.Name), $env:MOZILLABUILD) -severity 'INFO'

  $env:PIP_DOWNLOAD_CACHE = 'Y:\pip-cache'
  [Environment]::SetEnvironmentVariable('PIP_DOWNLOAD_CACHE', $env:PIP_DOWNLOAD_CACHE, 'Machine')
  Write-Log -message ('{0} :: environment PIP_DOWNLOAD_CACHE set ({1}).' -f $($MyInvocation.MyCommand.Name), $env:PIP_DOWNLOAD_CACHE) -severity 'INFO'
}
function New-LocalCache {
  param (
    [string[]] $paths = @(
      'y:\hg-shared',
      'y:\pip-cache',
      'y:\tooltool-cache'
    )
  )
  foreach ($path in $paths) {
    New-Item -Path $path -ItemType directory -force
    & 'icacls.exe' @($path, '/grant', 'Everyone:(OI)(CI)F')
  }
}

$lock = 'C:\dsc\in-progress.lock'
if (Test-Path -Path $lock -ErrorAction SilentlyContinue) {
  Write-Log -message 'userdata run aborted. lock file exists.' -severity 'INFO'
  exit
} else {
  $lockDir = [IO.Path]::GetDirectoryName($lock)
  if (-not (Test-Path -Path $lockDir -ErrorAction SilentlyContinue)) {
    New-Item -Path $lockDir -ItemType directory -force
  }
  New-Item $lock -type file -force
}
Write-Log -message 'userdata run starting.' -severity 'INFO'

tzutil /s UTC
Write-Log -message 'system timezone set to UTC.' -severity 'INFO'
W32tm /register
W32tm /resync /force
Write-Log -message 'system clock synchronised.' -severity 'INFO'

# set up a log folder, an execution policy that enables the dsc run and a winrm envelope size large enough for the dynamic dsc.
$logFile = ('{0}\log\{1}.userdata-run.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"))
New-Item -ItemType Directory -Force -Path ('{0}\log' -f $env:SystemDrive)

try {
  $userdata = (New-Object Net.WebClient).DownloadString('http://169.254.169.254/latest/user-data')
} catch {
  $userdata = $null
}
$publicKeys = (New-Object Net.WebClient).DownloadString('http://169.254.169.254/latest/meta-data/public-keys')

if ($publicKeys.StartsWith('0=aws-provisioner-v1-managed:')) {
  # provisioned worker
  $isWorker = $true
  $workerType = $publicKeys.Split(':')[1]
} else {
  # ami creation instance
  $isWorker = $false
  $workerType = $publicKeys.Replace('0=mozilla-taskcluster-worker-', '')
}
Write-Log -message ('isWorker: {0}.' -f $isWorker) -severity 'INFO'
$az = (New-Object Net.WebClient).DownloadString('http://169.254.169.254/latest/meta-data/placement/availability-zone')
Write-Log -message ('workerType: {0}.' -f $workerType) -severity 'INFO'
switch -wildcard ($az) {
  'eu-central-1*'{
    $dnsRegion = 'euc1'
  }
  'us-east-1*'{
    $dnsRegion = 'use1'
  }
  'us-west-1*'{
    $dnsRegion = 'usw1'
  }
  'us-west-2*'{
    $dnsRegion = 'usw2'
  }
}
Write-Log -message ('availabilityZone: {0}, dnsRegion: {1}.' -f $az, $dnsRegion) -severity 'INFO'

# if importing releng amis, do a little housekeeping
switch -wildcard ($workerType) {
  'gecko-t-*' {
    $runDscOnWorker = $false
    $renameInstance = $true
    $setFqdn = $true
    if (-not ($isWorker)) {
      Remove-LegacyStuff -logFile $logFile
      Set-Credentials -username 'root' -password ('{0}' -f [regex]::matches($userdata, '<rootPassword>(.*)<\/rootPassword>')[0].Groups[1].Value)
    }
    Map-DriveLetters
  }
  default {
    $runDscOnWorker = $true
    $renameInstance = $true
    $setFqdn = $true
  }
}

Get-ChildItem -Path $env:SystemRoot\Microsoft.Net -Filter ngen.exe -Recurse | % {
  try {
    & $_.FullName executeQueuedItems
    Write-Log -message ('executed: "{0} executeQueuedItems".' -f $_.FullName) -severity 'INFO'
  }
  catch {
    Write-Log -message ('failed to execute: "{0} executeQueuedItems"' -f $_.FullName) -severity 'ERROR'
  }
}

# rename the instance
$instanceId = ((New-Object Net.WebClient).DownloadString('http://169.254.169.254/latest/meta-data/instance-id'))
$dnsHostname = [System.Net.Dns]::GetHostName()
if ($renameInstance -and ([bool]($instanceId)) -and (-not ($dnsHostname -ieq $instanceId))) {
  [Environment]::SetEnvironmentVariable("COMPUTERNAME", "$instanceId", "Machine")
  $env:COMPUTERNAME = $instanceId
  (Get-WmiObject Win32_ComputerSystem).Rename($instanceId)
  $rebootReasons += 'host renamed'
  Write-Log -message ('host renamed from: {0} to {1}.' -f $dnsHostname, $instanceId) -severity 'INFO'
}
# set fqdn
if ($setFqdn) {
  if (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\NV Domain") {
    $currentDomain = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\" -Name "NV Domain")."NV Domain"
  } elseif (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Domain") {
    $currentDomain = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\" -Name "Domain")."Domain"
  } else {
    $currentDomain = $env:USERDOMAIN
  }
  $domain = ('{0}.{1}.mozilla.com' -f $workerType, $dnsRegion)
  if (-not ($currentDomain -ieq $domain)) {
    [Environment]::SetEnvironmentVariable("USERDOMAIN", "$domain", "Machine")
    $env:USERDOMAIN = $domain
    Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\' -Name 'Domain' -Value "$domain"
    Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\' -Name 'NV Domain' -Value "$domain"
    Write-Log -message ('domain set to: {0}' -f $domain) -severity 'INFO'
  }
}


if ($rebootReasons.length) {
  Remove-Item -Path $lock -force
  & shutdown @('-r', '-t', '0', '-c', [string]::Join(', ', $rebootReasons), '-f', '-d', 'p:4:1') | Out-File -filePath $logFile -append
} else {
  # create a scheduled task to run HaltOnIdle continuously
  if (Test-Path -Path 'C:\dsc\HaltOnIdle.ps1' -ErrorAction SilentlyContinue) {
    Remove-Item -Path 'C:\dsc\HaltOnIdle.ps1' -confirm:$false -force
    Write-Log -message 'C:\dsc\HaltOnIdle.ps1 deleted.' -severity 'INFO'
  }
  (New-Object Net.WebClient).DownloadFile(('https://raw.githubusercontent.com/mozilla-releng/OpenCloudConfig/master/userdata/HaltOnIdle.ps1?{0}' -f [Guid]::NewGuid()), 'C:\dsc\HaltOnIdle.ps1')
  Write-Log -message 'C:\dsc\HaltOnIdle.ps1 downloaded.' -severity 'INFO'
  & schtasks @('/create', '/tn', 'HaltOnIdle', '/sc', 'minute', '/mo', '2', '/ru', 'SYSTEM', '/rl', 'HIGHEST', '/tr', 'powershell.exe -File C:\dsc\HaltOnIdle.ps1', '/f')
  Write-Log -message 'scheduled task: HaltOnIdle, created.' -severity 'INFO'

  if (($runDscOnWorker)  -or (-not ($isWorker))) {
    switch -wildcard ((Get-WmiObject -class Win32_OperatingSystem).Caption) {
      'Microsoft Windows 7*' {
        Map-DriveLetters
        Run-Dsc32BitBypass
      }
      default {
        Set-ExecutionPolicy RemoteSigned -force | Out-File -filePath $logFile -append
        & winrm @('set', 'winrm/config', '@{MaxEnvelopeSizekb="8192"}')
        $transcript = ('{0}\log\{1}.dsc-run.log' -f $env:SystemDrive, [DateTime]::Now.ToString("yyyyMMddHHmmss"))
        Start-Transcript -Path $transcript -Append
        # this setting persists only for the current session
        Enable-PSRemoting -SkipNetworkProfileCheck -Force
        Run-RemoteDesiredStateConfig -url 'https://raw.githubusercontent.com/mozilla-releng/OpenCloudConfig/master/userdata/DynamicConfig.ps1' -workerType $workerType
        Stop-Transcript
        if (((Get-Content $transcript) | % { (($_ -match 'requires a reboot') -or ($_ -match 'reboot is required')) }) -contains $true) {
          Remove-Item -Path $lock -force
          & shutdown @('-r', '-t', '0', '-c', 'a package installed by dsc requested a restart', '-f', '-d', 'p:4:1') | Out-File -filePath $logFile -append
        }
      }
    }
    # create a scheduled task to run dsc at startup
    if (Test-Path -Path 'C:\dsc\rundsc.ps1' -ErrorAction SilentlyContinue) {
      Remove-Item -Path 'C:\dsc\rundsc.ps1' -confirm:$false -force
      Write-Log -message 'C:\dsc\rundsc.ps1 deleted.' -severity 'INFO'
    }
    (New-Object Net.WebClient).DownloadFile(('https://raw.githubusercontent.com/mozilla-releng/OpenCloudConfig/master/userdata/rundsc.ps1?{0}' -f [Guid]::NewGuid()), 'C:\dsc\rundsc.ps1')
    Write-Log -message 'C:\dsc\rundsc.ps1 downloaded.' -severity 'INFO'
    & schtasks @('/create', '/tn', 'RunDesiredStateConfigurationAtStartup', '/sc', 'onstart', '/ru', 'SYSTEM', '/rl', 'HIGHEST', '/tr', 'powershell.exe -File C:\dsc\rundsc.ps1', '/f')
    Write-Log -message 'scheduled task: RunDesiredStateConfigurationAtStartup, created.' -severity 'INFO'
  } else {
    switch -wildcard ((Get-WmiObject -class Win32_OperatingSystem).Caption) {
      'Microsoft Windows 7*' {
        New-LocalCache
      }
      default {
        Stop-DesiredStateConfig
        Remove-DesiredStateConfigTriggers
      }
    }
  }

  if (-not ($isWorker)) {
    Set-Credentials -username 'GenericWorker' -password ('{0}' -f [regex]::matches($userdata, '<workerPassword>(.*)<\/workerPassword>')[0].Groups[1].Value) -setautologon
  }

  # archive dsc logs
  Get-ChildItem -Path ('{0}\log' -f $env:SystemDrive) | ? { !$_.PSIsContainer -and $_.Name.EndsWith('.log') -and $_.Length -eq 0 } | % { Remove-Item -Path $_.FullName -Force }
  New-ZipFile -ZipFilePath $logFile.Replace('.log', '.zip') -Item @(Get-ChildItem -Path ('{0}\log' -f $env:SystemDrive) | ? { !$_.PSIsContainer -and $_.Name.EndsWith('.log') -and $_.FullName -ne $logFile } | % { $_.FullName })
  Write-Log -message ('log archive {0} created.' -f $logFile.Replace('.log', '.zip')) -severity 'INFO'
  Get-ChildItem -Path ('{0}\log' -f $env:SystemDrive) | ? { !$_.PSIsContainer -and $_.Name.EndsWith('.log') -and $_.FullName -ne $logFile } | % { Remove-Item -Path $_.FullName -Force }

  if ((-not ($isWorker)) -and (Test-Path -Path 'C:\generic-worker\run-generic-worker.bat' -ErrorAction SilentlyContinue)) {
    Remove-Item -Path $lock -force
    & shutdown @('-s', '-t', '0', '-c', 'dsc run complete', '-f', '-d', 'p:4:1') | Out-File -filePath $logFile -append
  } elseif ($isWorker) {
    if (-not (Test-Path -Path 'Z:\' -ErrorAction SilentlyContinue)) { # if the Z: drive isn't mapped, map it.
      Map-DriveLetters
    }
    if (Test-Path -Path 'C:\generic-worker\run-generic-worker.bat' -ErrorAction SilentlyContinue) {
      Write-Log -message 'generic-worker installation detected.' -severity 'INFO'
      New-Item 'C:\dsc\task-claim-state.valid' -type file -force
      # give g-w 2 minutes to fire up, if it doesn't, boot loop.
      $timeout = New-Timespan -Minutes 2
      $timer = [Diagnostics.Stopwatch]::StartNew()
      $waitlogged = $false
      while (($timer.Elapsed -lt $timeout) -and (@(Get-Process | ? { $_.ProcessName -eq 'generic-worker' }).length -eq 0)) {
        if (!$waitlogged) {
          Write-Log -message 'waiting for generic-worker process to start.' -severity 'INFO'
          $waitlogged = $true
        }
      }
      if ((@(Get-Process | ? { $_.ProcessName -eq 'generic-worker' }).length -eq 0)) {
        Write-Log -message 'no generic-worker process detected.' -severity 'INFO'
        & format @('Z:', '/fs:ntfs', '/v:""', '/q', '/y')
        Write-Log -message 'Z: drive formatted.' -severity 'INFO'
        #& net @('user', 'GenericWorker', (Get-ItemProperty -path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -name 'DefaultPassword').DefaultPassword)
        Remove-Item -Path $lock -force
        & shutdown @('-r', '-t', '0', '-c', 'reboot to rouse the generic worker', '-f', '-d', 'p:4:1') | Out-File -filePath $logFile -append
      } else {
        $timer.Stop()
        Write-Log -message ('generic-worker running process detected {0} ms after task-claim-state.valid flag set.' -f $timer.ElapsedMilliseconds) -severity 'INFO'
      }
    }
  }
}
Remove-Item -Path $lock -force
Write-Log -message 'userdata run completed' -severity 'INFO'
