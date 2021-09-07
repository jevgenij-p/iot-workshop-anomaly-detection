<#
    .SYNOPSIS
    Creates a random key.

    .DESCRIPTION
    Creates a random string used as a primary or secondary key for Azure resources.

    .EXAMPLE
    Get-RandomKey
#>
function Get-RandomKey {
    $length=32
    $randomString=-join (((33..126)) * 100 | Get-Random -Count $length | %{[char]$_})
    $bytes=[System.Text.Encoding]::Unicode.GetBytes($randomString)
    $key=[Convert]::ToBase64String($bytes)
    return $key
}

<#
    .SYNOPSIS
    Creates a string, containing random letters and numbers.

    .DESCRIPTION
    Creates a string, containing random lower-case letters and numbers.
    Takes a length of the string.

    .PARAMETER length
    Specifies the length of the random string.

    .EXAMPLE
    Get-RandomLowercaseAndNumbers 16
#>
function Get-RandomLowercaseAndNumbers {
    Param([int]$length)

    $randomString=-join (((48..57)+(97..122)) * 100 | Get-Random -Count $length | %{[char]$_})
    return $randomString
}