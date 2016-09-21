import module namespace m='http://www.tei-c.org/tei-simple/models/beamer.odd/epub' at '/db/apps/tei-publisher/transform/beamer-epub.xql';

declare variable $xml external;

declare variable $parameters external;

let $options := map {
    "styles": ["../transform/beamer.css"],
    "collection": "/db/apps/tei-publisher/transform",
    "parameters": if (exists($parameters)) then $parameters else map {}
}
return m:transform($options, $xml)