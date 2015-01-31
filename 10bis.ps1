# How to run:
# .\10bis.ps1 your_email your_password
#
# Output:
# A CSV file with your purchase history. The file will be saved in the working directory.
#
# Configurable parameters:
# stopAfterEmptyMonths - change this if you had long gaps in using 10bis.

Param($email, $password)

$stopAfterEmptyMonths = 6

$CookieContainer = New-Object System.Net.CookieContainer
	
Function HttpPost($url, $content)
{
	[net.httpWebRequest] $req = [net.webRequest]::create($url)
	$req.method = "POST"
	$req.ContentType = "application/json; charset=UTF-8"
	$req.CookieContainer = $CookieContainer
	$reqst = $req.getRequestStream()
	$buffer = [text.encoding]::ascii.getbytes($content)
	$reqst.write($buffer, 0, $buffer.length)
	$reqst.flush()
	$reqst.close()
	[net.httpWebResponse] $res = $req.getResponse()
	$resst = $res.getResponseStream()
	$sr = new-object IO.StreamReader($resst)
	$result = $sr.ReadToEnd()
	$res.close()
	$result
}

Function HttpGetHtml($url)
{
	$tempFile = "$((Get-Location).Path)\page$(get-date -f yyyyMMddHHmmssfff).html"
	$wc = new-object net.webclient
	$wc.Headers.add("Cookie", $CookieContainer.GetCookieHeader($url))
	$wc.DownloadFile($url, $tempFile)
	
	add-type -Path "HtmlAgilityPack.dll"
	$doc = New-Object HtmlAgilityPack.HtmlDocument 
	$doc.Load($tempFile, [System.Text.Encoding]::UTF8) 
	Remove-Item $tempFile -ErrorAction SilentlyContinue
	$doc
}

Function Login($email, $password)
{
	$url = New-Object System.Uri("https://www.10bis.co.il/Account/LogonAjax")
	$content = "{`"model`":{`"UserName`":`"$email`",`"Password`":`"$password`"}}"
	$responseText = HttpPost $url $content
	if (-Not $responseText.Contains('"LogingSuccess":true')) {
		throw "Error logging in. Response is: $responseText"
	}
}

Function GetMonthData($monthsAgo)
{
	$doc = HttpGetHtml "https://www.10bis.co.il/Account/UserReport?dateBias=-$monthsAgo"
	$rows = $doc.DocumentNode.SelectNodes("//tr[@class='reportDataTr']")
	
	if (-Not $rows) {
		Write-Host "$monthsAgo months ago: no entries"
		return $false
	}
	
	$data = $rows | % {
		$row = $_		
		$date = $row.SelectSingleNode("td[2]").InnerText.Trim() 
		$time = $row.SelectSingleNode("td[3]").InnerText.Trim() 
		$restaurant = $row.SelectSingleNode("td[4]").InnerText.Trim() 
		$price = $row.SelectSingleNode("td[6]").InnerText.Trim().substring(1)
		New-Object PsObject -Property @{ Date = $date; Time = $time; Restaurant = $restaurant; Price = $price } | 
			Select Date, Time, Restaurant, Price 
	}

	Write-Host "$monthsAgo months ago: added $($rows.Count) entries"
	[array]::Reverse($data)
	$data
}

Function ExportToCsv($data) {
	$csvFileName = ".\report$(get-date -f yyyyMMddHHmmssfff).csv"
	$data | Export-Csv $csvFileName -encoding "UTF8" -notype
	Write-Host "Exported to $csvFileName"
}


if (-Not $email) { throw "Please specify email" }
if (-Not $password) { throw "Please specify password" }
Login $email $password

$emptyMonths = 0
$monthsAgo = 0
$data = @()
do {
	$monthData = GetMonthData $monthsAgo
	if ($monthData) { 
		$data += $monthData
		$emptyMonths = 0
	} 
	else { $emptyMonths++ }	
	$monthsAgo++
}
while ($emptyMonths -le $stopAfterEmptyMonths)
Write-Host "Reached stop condition: $stopAfterEmptyMonths empty months."

ExportToCsv($data)
