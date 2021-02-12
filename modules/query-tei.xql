(:
 :
 :  Copyright (C) 2017 Wolfgang Meier
 :
 :  This program is free software: you can redistribute it and/or modify
 :  it under the terms of the GNU General Public License as published by
 :  the Free Software Foundation, either version 3 of the License, or
 :  (at your option) any later version.
 :
 :  This program is distributed in the hope that it will be useful,
 :  but WITHOUT ANY WARRANTY; without even the implied warranty of
 :  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 :  GNU General Public License for more details.
 :
 :  You should have received a copy of the GNU General Public License
 :  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 :)
xquery version "3.1";

module namespace teis="http://www.tei-c.org/tei-simple/query/tei";

declare namespace tei="http://www.tei-c.org/ns/1.0";

import module namespace config="http://www.tei-c.org/tei-simple/config" at "config.xqm";
import module namespace nav="http://www.tei-c.org/tei-simple/navigation/tei" at "navigation-tei.xql";
import module namespace query="http://www.tei-c.org/tei-simple/query" at "query.xql";
import module namespace console="http://exist-db.org/xquery/console";

declare function teis:query-default($fields as xs:string+, $query as xs:string, $target-texts as xs:string*,
    $sortBy as xs:string*) {

        let $request := map {
            "parameters": map {
                "sort": if ($sortBy) then $sortBy else $config:default-sort,
                "targets": $target-texts,
                "query": $query
            }
        }

        let $matches := teis:query-document($request) 

        for $match in $matches 
            return
            $match//tei:text
};

declare function teis:query-metadata($field as xs:string, $query as xs:string, $sort as xs:string) {
    let $request := map {
            "parameters": map {
                "sort": if ($sort) then $sort else $config:default-sort,
                $config:search-fields?($field): $query
            }
        }

    let $matches := teis:query-document($request) 

    return 
        $matches
};

declare function teis:autocomplete($doc as xs:string?, $fields as xs:string+, $q as xs:string) {
    for $field in $fields
    return
        switch ($field)
            case "author" return
                collection($config:data-root)/ft:index-keys-for-field("author", $q,
                    function($key, $count) {
                        $key
                    }, 30)
            case "file" return
                collection($config:data-root)/ft:index-keys-for-field("file", $q,
                    function($key, $count) {
                        $key
                    }, 30)
            case "text" return
                if ($doc) then (
                    doc($config:data-root || "/" || $doc)/util:index-keys-by-qname(xs:QName("tei:div"), $q,
                        function($key, $count) {
                            $key
                        }, 30, "lucene-index"),
                    doc($config:data-root || "/" || $doc)/util:index-keys-by-qname(xs:QName("tei:text"), $q,
                        function($key, $count) {
                            $key
                        }, 30, "lucene-index")
                ) else (
                    collection($config:data-root)/util:index-keys-by-qname(xs:QName("tei:div"), $q,
                        function($key, $count) {
                            $key
                        }, 30, "lucene-index"),
                    collection($config:data-root)/util:index-keys-by-qname(xs:QName("tei:text"), $q,
                        function($key, $count) {
                            $key
                        }, 30, "lucene-index")
                )
            case "head" return
                if ($doc) then
                    doc($config:data-root || "/" || $doc)/util:index-keys-by-qname(xs:QName("tei:head"), $q,
                        function($key, $count) {
                            $key
                        }, 30, "lucene-index")
                else
                    collection($config:data-root)/util:index-keys-by-qname(xs:QName("tei:head"), $q,
                        function($key, $count) {
                            $key
                        }, 30, "lucene-index")
            default return
                collection($config:data-root)/ft:index-keys-for-field("title", $q,
                    function($key, $count) {
                        $key
                    }, 30)
};

declare function teis:get-parent-section($node as node()) {
    ($node/self::tei:text, $node/ancestor-or-self::tei:div[1], $node)[1]
};

declare function teis:get-breadcrumbs($config as map(*), $hit as node(), $parent-id as xs:string) {
    let $work := root($hit)/*
    let $work-title := nav:get-document-title($config, $work)/string()
    return
        <div class="breadcrumbs">
            <a class="breadcrumb" href="{$parent-id}">{$work-title}</a>
            {
                for $parentDiv in $hit/ancestor-or-self::tei:div[tei:head]
                let $id := util:node-id(
                    if ($config?view = "page") then ($parentDiv/preceding::tei:pb[1], $parentDiv)[1] else $parentDiv
                )
                return
                    <a class="breadcrumb" href="{$parent-id || "?action=search&amp;root=" || $id || "&amp;view=" || $config?view || "&amp;odd=" || $config?odd}">
                    {$parentDiv/tei:head/string()}
                    </a>
            }
        </div>
};

(:~
 : Expand the given element and highlight query matches by re-running the query
 : on it.
 :)
declare function teis:expand($data as node()) {
    let $query := session:get-attribute($config:session-prefix || ".query")
    let $field := session:get-attribute($config:session-prefix || ".field")
    let $div :=
        if ($data instance of element(tei:pb)) then
            let $nextPage := $data/following::tei:pb[1]
            return
                if ($nextPage) then
                    if ($field = "text") then
                        (
                            ($data/ancestor::tei:div intersect $nextPage/ancestor::tei:div)[last()],
                            $data/ancestor::tei:text
                        )[1]
                    else
                        $data/ancestor::tei:text
                else
                    (: if there's only one pb in the document, it's whole
                      text part should be returned :)
                    if (count($data/ancestor::tei:text//tei:pb) = 1) then
                        ($data/ancestor::tei:text)
                    else
                      ($data/ancestor::tei:div, $data/ancestor::tei:text)[1]
        else
            $data
    let $result := teis:query-default-view($div, $query, $field)
    let $expanded :=
        if (exists($result)) then
            util:expand($result, "add-exist-id=all")
        else
            $div
    return
        if ($data instance of element(tei:pb)) then
            $expanded//tei:pb[@exist:id = util:node-id($data)]
        else
            $expanded
};


declare %private function teis:query-default-view($context as element()*, $query as xs:string, $fields as xs:string+) {
    for $field in $fields
    return
        switch ($field)
            case "head" return
                $context[./descendant-or-self::tei:head[ft:query(., $query, $query:QUERY_OPTIONS)]]
            default return
                $context[./descendant-or-self::tei:div[ft:query(., $query, $query:QUERY_OPTIONS)]] |
                $context[./descendant-or-self::tei:text[ft:query(., $query, $query:QUERY_OPTIONS)]]
};

declare function teis:get-current($config as map(*), $div as node()?) {
    if (empty($div)) then
        ()
    else
        if ($div instance of element(tei:teiHeader)) then
            $div
        else
            (nav:filler($config, $div), $div)[1]
};

declare function teis:prepare-fulltext-query($request) {
    for $q in $request?parameters?query 
            let $decoded := xmldb:decode($q)
            return 
                if ($decoded) then 
                    $decoded
                else
                    ()
};

declare function teis:prepare-facet-query($request) {
    map:merge((
        for $dimension in map:keys($config:search-facets)
            return
                (: only add the dimensions with specified criteria :)
                if ($request?parameters('facet-'||$dimension)) then
                    map {
                        (: map search parameters to local facet dimension names :)
                        $config:search-facets($dimension): $request?parameters('facet-'||$dimension)
                    }
                else
                    ()
    ))
};

declare function teis:prepare-range-query($request) {
    for $item in $config:search-range
            let $field := $item?field

            let $from:= $request?parameters($item?inputs?from)
            let $to:= $request?parameters($item?inputs?to)

            return 
                if ($from or $to) then
                    (: create range query :)
                    if ($from and $to) then
                        $field || ':[' || $from || ' TO ' || $to || ']'
                    else if ($from) then
                        $field || ':[' || $from || ' TO *]'
                    else
                        $field || ':[* TO ' || $to || ']'
                else
                    ()
};

declare function teis:prepare-field-query($request) {
    for $f in map:keys($config:search-fields)
        let $q := 
            for $p in $request?parameters($f) 
                let $query := xmldb:decode($p)
                return if ($query) then $query else ()

        return
            if (count($q)) then 
                $config:search-fields($f) || ':(' || 
                string-join($q, teis:conjunction($request?parameters($f || '-operator'))) || ')' 
            else 
                ()
};

declare function teis:query-document($request as map(*)) {

    let $facet-query := teis:prepare-facet-query($request)
    let $text-query := teis:prepare-fulltext-query($request)
    let $range-query := teis:prepare-range-query($request)
    let $field-query := teis:prepare-field-query($request)

    let $targets := $request?parameters?target-texts

    let $fields := 
        for $f in map:keys($config:search-fields)
            return 
                $config:search-fields($f)

    let $constraints := 
        (
            if (count($text-query)) then $text-query else (),
            if (count($range-query)) then $range-query else (),
            $field-query
        )

    let $query := string-join($constraints, ' AND ')

    (: Find matches across data-root collections :)
    (: TODO: allow to query specific indexes, e.g. only for headings :)
    let $hits :=
        if ($targets) then
            for $text in $targets 
            return
                $config:data-root ! doc(. || "/" || $text)//tei:text[ft:query(., $query, teis:query-options($fields, $facet-query))]
        else
            for $root in $config:data-root
                let $c:= console:log($root)

            return
                collection($root)//tei:text[ft:query(., $query, teis:query-options($fields, $facet-query))]

    (: Order by incoming sort parameter :)
    let $sort := ($request?parameters?sort, $config:default-sort)[1]

    let $sorted := 
        for $i in $hits
            let $f := ft:field($i, $sort)
            order by $f[1]
            return $i/ancestor::tei:TEI

    return 
        $sorted
};

declare function teis:conjunction($operator) {
    switch ($operator) 
        case "and"
            return ' AND '
        default
            return ' OR '
};

declare function teis:query-options($sort, $facets) {
     map:merge((
        $query:QUERY_OPTIONS,
        map {
            "facets": $facets
        } ,
        map { "fields": $sort}
    ))
};