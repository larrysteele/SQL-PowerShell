#variables
$msbuildPath = 'C:\Program Files (x86)\MSBuild\14.0\Bin\msbuild.exe'
$projectPath = 'C:\TFS\SampleProjects\SalesDb\SalesDb'
$dacPath = "$projectPath\bin\debug\salesdb.dacpac"
#$sqlPkg = 'C:\Program Files (x86)\Microsoft SQL Server\120\DAC\bin\SqlPackage.exe'
$sqlPkg = 'C:\Program Files (x86)\Microsoft Visual Studio 14.0\Common7\IDE\Extensions\Microsoft\SQLDB\DAC\120\SqlPackage.exe'
$application = 'SalesDB'
$env = 'Test'
$dbServer = 'localhost'
$sqlDb = 'salesdb'
$profilePath = "$projectPath\Profiles\SalesDb.publish.xml"
$permissionPath = $null

#build project with MSBUILD to create dacpac sql package
& $msbuildPath $projectPath\salesdb.sqlproj

function runSqlPublish{
param(
    [string] $dbServer,
    [string] $sqlDb,
    [string] $sqlFile,
    [string] $dacPath,
    [string] $profilePath,
    [string] $permissionPath,
    [string] $sqlPkg
    )

	try
	{
		#to be used with action:publish $parameters = "{DatabaseRoles | FileGroups | ExtendedProperties | RoleMembership | Users | ServerRoleMemberShip | ServerRoles}"
		$vsdbcmdArgs = "/Action:Script /SourceFile:""$dacPath"" /TargetConnectionString:""Data Source=$dbServer;Integrated Security=False;Initial Catalog=$sqlDb;"" /Profile:""$profilePath"" /OutputPath:""$sqlFile"""
		Write-Output "$vsdbcmdArgs"

		# Build Startinfo and set options according to parameters
		$startinfo = new-object System.Diagnostics.ProcessStartInfo 
		$startinfo.FileName = $sqlPkg
		$startinfo.Arguments = $vsdbcmdArgs
		$startinfo.WindowStyle = "Hidden"
		$startinfo.CreateNoWindow = $TRUE
		$startinfo.UseShellExecute = $FALSE
		$startinfo.RedirectStandardOutput = $TRUE
		$startinfo.RedirectStandardError = $TRUE
		$process = [System.Diagnostics.Process]::Start($startinfo)
		Write-Output  $process.StandardOutput.ReadToEnd()
		Write-Output  $process.StandardError.ReadToEnd()
		$process.WaitForExit()

		$lines = Get-Content $sqlFile
		$lines = Foreach ($line in $lines) { $line -Replace ":setvar .+", "" }
		$lines = Foreach ($line in $lines) { $line -Replace ":on error .+", "" }
		$lines = Foreach ($line in $lines) { $line -Replace "USE \[.+\]", "" }
		$lines = Foreach ($line in $lines) { $line -Replace "IF N'.+__IsSqlCmdEnabled.+", "IF 1=2" }
		$lines = Foreach ($line in $lines) { $line -Replace "EXECUTE sp_droprolemember.+", "" }
		$lines = Foreach ($line in $lines) { $line -Replace "DROP USER.+", "" }
		$lines = Foreach ($line in $lines) { $line -Replace "DROP ROLE.+", "" }
		$lines = Foreach ($line in $lines) { $line -Replace "DROP SCHEMA.+", "" }
		Set-Content $sqlFile $lines

		#Add-PSSnapin SqlServerProviderSnapin120
		#Add-PSSnapin SqlServerCmdletSnapin120
		Write-Output "Run '$sqlFile' on $dbServer/$sqlDb"
		Invoke-Sqlcmd -InputFile "$sqlFile" -Database "$sqlDb" -ServerInstance "$dbServer" -Verbose -ErrorAction Stop

		if(!([string]::IsNullOrEmpty($permissionPath)))
		{
			Write-Output "Run '$sqlFile' on $deployDbServer/$deployDb"
			Invoke-Sqlcmd -InputFile $permissionPath -Database "$sqlDb" -ServerInstance "$dbServer"
		}
	}

	catch
	{
		Write-Error $_.Exception.Message
		exit 1
	}    
}

function runSqlDiffReport{
param(
    [string] $dbServer,
    [string] $sqlDb,
    [string] $dacPath,
    [string] $outPutResultPath,
    [string] $profilePath,
    [string] $sqkPkg
    )

	try
	{
		Write-Output "& "$sqlPkg" /action:DeployReport /TargetConnectionString:'Data Source='$dbServer';Initial Catalog='$sqlDb'' /SourceFile:$dacPacPath /profile:$profilePath /OutputPath:$outPutResultPath"
        & "$sqlPkg" /action:DeployReport /TargetConnectionString:'Data Source='$dbServer';Initial Catalog='$sqlDb'' /SourceFile:$dacPath /profile:$profilePath /OutputPath:$outPutResultPath
	}

	catch
	{
		Write-Error $_.Exception.Message
		exit 1
	}
}

try
{
    $targetReleaseOutput = $projectPath + "\" + $application + "\" + $env
    if(!(Test-Path -Path $targetReleaseOutput ))
    {
        New-Item -ItemType directory -Path $targetReleaseOutput
    }

    $date = (Get-Date).ToString("s").Replace(":","-") 
 
    $outPutResultPath = $targetReleaseOutput + "\" + "DiffReport" + "_" + $date + ".xml"
    $sqlFile = $targetReleaseOutput + "\" + $env + "-" + $sqlDb + "-" + $date + "_schema.sql"

    #runSqlDiffReport $dbServer $sqlDb $dacPath $outPutResultPath $profilePath $sqPkg
    runSqlPublish $dbServer $sqlDb $sqlFile $dacPath $profilePath $permissionPath $sqlPkg

}

catch
{
    Write-Error $_.Exception.Message
    exit 1
}
