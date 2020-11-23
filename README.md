# Magic property

The patch files for registering SPARQL magic properties onto AllegroGraph.

## Install

Upload `wf_path.fasl` and `libannoy.so` to `/path-to-ag/lib/patches` first, where `/path-to-ag` is the path that the Allegrograph is installed. If `patches` folder does not exist, please create it.

After uploading, restart AllegroGraph.

## FastText

### `<http://example.org/fasttext#mostSimilar>`

This property accepts 3 arguments:

1. `word` -- the word for querying similarity
2. `topn` -- the amount of similar words to be retrieved; *optional*, default to be `10`
3. `api`  -- the API url of the FastText web service; *optional*, default to be the value of environment varibale `FASTTEXT_API_URL`

#### Examples

**Please note that, the API url of the FastText web service must be accesible from AllegroGraph server.**

* query by word

```sparql
SELECT ?sims WHERE {
  ?sims <http://example.org/fasttext#mostSimilar> "computers" .
}
```

* query by word but only take 5 similar tokens

```sparql
SELECT ?sims WHERE {
  ?sims <http://example.org/fasttext#mostSimilar> ("computers" 5) .
}
```

* query by word, take 8 tokens, explicitly specify API url

```sparql
SELECT ?sims WHERE {
  ?sims <http://example.org/fasttext#mostSimilar> ("computers" 8 "http://localhost:8080/most-similar") .
}
```

## TransE

Please use `ag-transe-cli` to populate the knowledge graph first.

Meanwhile, these 3 environment variables must be provided to Allegrograph during starting its server:

1. `ANNOY_INDEX_PATH` -- the path to the pre-trained annoy index file; it must be accesible by AllegroGraph
2. `ANNOY_INDEX_DIM` -- dimensionality of the embeddings
3. `ANNOY_INDEX_METRIC` -- the metric for measuring similarities, e.g. "angular", "dot"

For example:

```bash
export ANNOY_INDEX_PATH="/usr/local/data/annoy_index"
export ANNOY_INDEX_DIM="200"
export ANNOY_INDEX_METRIC="angular"
```

`ANNOY_INDEX_DIM` and `ANNOY_INDEX_METRIC` must be consistent of the pre-trained annoy index file `ANNOY_INDEX_PATH`.

### `<http://example.org/embeddings#hasID>`

Entities and relations can be referenced by their IDs, which are the same from TransE model's traning data.

```sparql
SELECT ?ent WHERE {
  ?ent a rdfs:Class .
  ?ent <http://example.org/embeddings#hasID> 100 .
}
```

### `<http://example.org/embeddings#getEmbedding>`

It takes the `entity` as argument and return the corresponding embedding vector as a JSON array (string) that can be deserialised back by any programming language.

```sparql
SELECT ?ent ?embed WHERE {
  ?ent <http://example.org/embeddings#hasID> 100 .
  ?embed <http://example.org/embeddings#getEmbedding> ?ent .
}
```

### `<http://example.org/embeddings#mostSimilar>`

This property accepts 2 arguments:

1. `word` -- the word for querying similarity
2. `topn` -- the amount of similar words to be retrieved; *optional*, default to be `10`

* query similar entities of #100 entity

```sparql
SELECT ?ent ?similarEnts WHERE {
  ?ent <http://example.org/embeddings#hasID> 100 .
  ?similarEnts <http://example.org/embeddings#mostSimilar> ?ent .
}
```

* query 5 similar entities of #100 entity

```sparql
SELECT ?ent ?similarEnts WHERE {
  ?ent <http://example.org/embeddings#hasID> 100 .
  ?similarEnts <http://example.org/embeddings#mostSimilar> (?ent 5) .
}
```
