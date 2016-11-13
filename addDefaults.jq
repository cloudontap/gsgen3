# Apply f to composite entities recursively, and to atoms
def walk($parentKey):
  . as $in
  | if type == "object" then
      reduce keys[] as $key
        ( {}; . + { ($key):  ($in[$key] | walk($key)) } ) |
            if (.Id|not) and $parentKey then
                .Id = $parentKey
            else
                .
            end |
                if (.Name|not) and .Id then
                    .Name = .Id
                else
                    .
                end
  elif type == "array" then map( walk(null) )
  else
    .
  end;

walk(null)
