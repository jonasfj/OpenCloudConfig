<#
This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at http://mozilla.org/MPL/2.0/.
#>

function Validate-All {
  #[CmdletBinding()]
  param(
    [object] $validations
  )
  begin {}
  process {
    return (
      # if no validations are specified, this function will return $false and cause the calling resource's set script to be run
      (
        (($validations.PathsExist) -and ($validations.PathsExist.Length -gt 0)) -or
        (($validations.PathsNotExist) -and ($validations.PathsNotExist.Length -gt 0)) -or
        (($validations.CommandsReturn) -and ($validations.CommandsReturn.Length -gt 0)) -or
        (($validations.FilesContain) -and ($validations.FilesContain.Length -gt 0))
      ) -and (
        Validate-PathsExistOrNotRequested -items $validations.PathsExist
      ) -and (
        Validate-PathsNotExistOrNotRequested -items $validations.PathsNotExist
      ) -and (
        Validate-CommandsReturnOrNotRequested -items $validations.CommandsReturn
      ) -and (
        Validate-FilesContainOrNotRequested -items $validations.FilesContain
      )
    )
  }
  end {}
}

function Validate-PathsExistOrNotRequested {
  #[CmdletBinding()]
  param(
    [object[]] $items
  )
  begin {}
  process {
    # either no validation paths-exist are specified
    return ((-not ($items)) -or (
      # validation paths-exist are specified
      (($items) -and ($items.Length -gt 0)) -and
      # all validation paths-exist are satisfied (exist on the instance)
      (-not (@($items | % {
        (Test-Path -Path $_ -ErrorAction SilentlyContinue)
      }) -contains $false))
    ))
  }
  end {}
}

function Validate-PathsNotExistOrNotRequested {
  #[CmdletBinding()]
  param(
    [object[]] $items
  )
  begin {}
  process {
    # either no validation paths-exist are specified
    return ((-not ($items)) -or (
      # validation paths-exist are specified
      (($items) -and ($items.Length -gt 0)) -and
      # all validation paths-exist are satisfied (exist on the instance)
      (-not (@($items | % {
        (-not (Test-Path -Path $_ -ErrorAction SilentlyContinue))
      }) -contains $false))
    ))
  }
  end {}
}

function Validate-CommandsReturnOrNotRequested {
  #[CmdletBinding()]
  param(
    [object[]] $items
  )
  begin {}
  process {
    # either no validation commands-return are specified
    return ((-not ($items)) -or (
      # validation commands-return are specified
      (($items) -and ($items.Length -gt 0)) -and
      # all validation commands-return are satisfied
      (-not (@($items | % {
        $cr = $_
        @(@(& $cr.Command $cr.Arguments) | ? {
          $_ -match $cr.Match
        })
      }) -contains $false))
    ))
  }
  end {}
}

function Validate-FilesContainOrNotRequested {
  #[CmdletBinding()]
  param(
    [object[]] $items
  )
  begin {}
  process {
    # either no validation files-contain are specified
    return ((-not ($items)) -or (
      # validation files-contain are specified
      (($items) -and ($items.Length -gt 0)) -and
      # all validation files-contain are satisfied
      (-not (@($items | % {
        $fc = $_
        (((Get-Content $fc.Path) | % {
          $_ -match $fc.Match
        }) -contains $true) # a line within the file contained a match
      }) -contains $false)) # no files failed to contain a match (see '-not' above)
    ))
  }
  end {}
}