#Implement log function
function logit($level, $message)

	switch($level)
	{
	
		2 {$prefix = "WARNING: "}
		3 {$prefix = "ERROR: "}
		default {$prefix = "UNKNOWN"}
	}
}

#Connect to the Microsoft Online Service

Connect-MsolService

#Set domain variable
Logit 1 "Gettting Domain Variable..."
$domain = Get-MsolDomain | where {$_.Name -notlike "*mail*"}

#Set configuration directory location
Logit 1 "Settting path to HR export file..."
$dir = "C:\Configuration\HRExports"

#CSV HR export file to import in Azure Active Directory
Logit 1 "Import Users and assign License...."
(get-content "$($dir)\NewHire.csv") | foreach-object {$_ -replace "contoso.com" , $domain.Name} | Set-Content "$($dir)\NewHire.csv"