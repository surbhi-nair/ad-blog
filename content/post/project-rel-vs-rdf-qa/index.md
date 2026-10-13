---
title: "Comparison of Relational and RDF data model for Question Answering"
date: 2026-04-08T18:21:14+02:00
author: "Surbhi Nair"
authorAvatar: "img/author_sn.jpg"
tags: ["SPARQL", "GRASP"]
categories: []
image: "img/thumbnail.png"
---
We're exploring whether the way data is modeled - Relational or RDF - impacts question answering quality in the semantic parsing setting.
<!--more-->
We converted relational databases from the BIRD-SQL Mini-dev benchmark into RDF knowledge graphs and ran natural language questions through two agents, CHESS (Text2SQL) and GRASP (Text2SPARQL), on the same underlying data. This post covers how we set up the comparison, how it was evaluated fairly across both paradigms, and what the results show.

The evaluation scripts and final results are available in my [GitHub repository](https://github.com/surbhi-nair/rel-vs-rdf-qa).

## Content

- [Motivation](#motivation)
- [Goal](#goal)
- [Implementation](#implementation)
    - [The base benchmark: BIRD-SQL](#BIRD)
    - [Converting to RDF](#converting-to-rdf)
    - [The Contenders](#the-contenders)
        - [Text2SPARQL: GRASP](#text2sparql-grasp)
        - [Text2SQL: CHESS](#text2sql-chess)
- [Evaluation Setup](#evaluation-setup)
    - [What does the BIRD benchmark use?](#what-does-the-bird-benchmark-use)
    - [Relaxed F1 Score](#relaxed-f1-score)
    - [LLM-as-Judge Evaluation](#llm-as-judge-evaluation)
        - [With Ground Truth Output](#with-ground-truth-output-accuracy-judge)
        - [Without Ground Truth Output](#without-ground-truth-output)
- [Results](#results)
    - [Accuracy Results](#accuracy-results)
        - [F1 Score Results](#f1-score)
        - [LLM Judge Results](#llm-judge)
    - [Blind Comparison Results](#without-ground-truth)
    - [Cost Comparison](#cost-comparison)
- [Ablation](#ablation)
    - [Evidence vs No Evidence](#evidence-vs-no-evidence)
    - [Generic vs Semantic RDF](#generic-vs-semantic-rdf)
    - [Accuracy Judge Without the Queries](#accuracy-judge-with-gold-query-vs-without)
- [Conclusion](#conclusion)

## Motivation
Natural language interfaces to structured data follow the same basic idea: take a question in natural language, generate a formal query to get data from the underlying data source, get an answer. 

The two paradigms - SQL over relational databases, and SPARQL over RDF knowledge graphs - have been doing it completely separately from each other. To the best of our knowledge, there's no direct comparison on the same data with the same questions. We want to see how the two actually compare when put on equal footing?

There's also a measurement problem. Most relational benchmark evaluations rely on exact match, execution accuracy, or F1 scores - metrics that don't translate cleanly to our experimental setup.

## Goal
To compare the two paradigms fairly, we need to:

- Take a standard, well-established Text2SQL benchmark and convert its databases into RDF knowledge graphs.
- Run a Text2SQL agent and a Text2SPARQL agent on the same questions against their respective representations.
- Evaluate both systems using metrics that are fair to both paradigms.

## Implementation

The first decision was which relational QA benchmark to pick. The criteria were simple: it had to be realistic, well-maintained, publicly available ground truth queries, and already have a strong leaderboard to pick our Text2SQL contender from. The most popular benchmarks currently are SPIDER and BIRD.

- [Spider](https://yale-lily.github.io/spider) - the classic cross-domain benchmark but its databases are deliberately clean and small, designed to test schema understanding rather than real-world data handling. Too clean and too old for our purposes.
- [Spider 2.0](https://spider2-sql.github.io/) - the successor, designed for enterprise-scale complexity with much larger schemas, real company data, and substantially harder queries. But its sheer complexity and scale make it expensive and impractical to convert and run in a controlled comparison.
- [BIRD-SQL](https://bird-bench.github.io/) (**BI**g Bench for La**R**ge-scale **D**atabase Grounded Text-to-SQL Evaluation) is the one we picked. BIRD is grounded in real-world, noisy databases across 37+ domains. Its questions are designed to reflect practical user needs, and it has a strong leaderboard with open-source baselines. It's also more manageable in size for our purposes - especially since it provides the mini-dev subset.

### BIRD
The full BIRD benchmark has 12,751 question-SQL pairs across 95 databases split as:
| Split | # Databases | # Questions |
|---|---|---|
| Train | 69 | 9428 |
| Dev | 11 | 1534 |
| Test | 15 | 1789 |

The splits are database-disjoint i.e. each split has entirely different databases. Our Text2SQL and Text2SPARQL agents don't involve any training, so the train/dev distinction doesn't really apply here. But the distinction between dev and test is still relevant, since the test set is held out for leaderboard evaluation and does not provide the ground truth SQL queries to the public. 

So, the split that we need to work with is the dev set. But for the scope of the project, we picked the [Mini-dev](https://github.com/bird-bench/mini_dev) subset of the dev split as it is feasible to convert and run both agents on.

#### BIRD-SQL Mini-dev
Mini-dev is a lite version of the full dev set, designed by the BIRD team itself as a representative sample for quick evaluation cycles. It contains the same 11 set of databases from the dev split and a carefully selected set of 500 question-SQL instances. Below are some key statistics of the mini-dev dataset:

**Difficulty Distribution**
| Difficulty | # Questions | % of Total |
|---|---|---|
| Simple | 148 | 30% |
| Moderate | 250 | 50% |
| Challenging | 102 | 20% |

**Database Distribution and Schema**
| Database                | Tables | Columns | FKs | Rows      | # Questions |
|-------------------------|--------|---------|-----|-----------|-------------|
| california_schools      | 3      | 89      | 2   | 29,941    | 30          |
| card_games              | 6      | 115     | 4   | 803,445   | 52          |
| codebase_community      | 8      | 71      | 13  | 740,646   | 49          |
| debit_card_specializing | 5      | 21      | 1   | 423,050   | 30          |
| european_football_2     | 7      | 199     | 31  | 222,796   | 51          |
| financial               | 8      | 55      | 8   | 1,079,680 | 32          |
| formula_1               | 13     | 94      | 19  | 493,257   | 66          |
| student_club            | 8      | 48      | 8   | 42,511    | 48          |
| superhero               | 10     | 31      | 11  | 10,614    | 52          |
| thrombosis_prediction   | 3      | 64      | 2   | 15,252    | 50          |
| toxicology              | 4      | 11      | 5   | 36,922    | 40          |

- Schema complexity varies widely - `toxicology` has just 4 tables and 11 columns with 5 FKs, while `card_games` has 6 tables and 115 columns with 4 FKs.
- Row counts range from 10k in `superhero` to over 1 million in `financial`, reflecting a mix of small and large datasets.

<details>
<summary> Database Breakdown by Difficulty </summary>

| Database | Simple | Moderate | Challenging | Total |
|---|---|---|---|---|
| california_schools | 8 | 17 | 5 | 30 |
| card_games | 13 | 33 | 6 | 52 |
| codebase_community | 21 | 23 | 5 | 49 |
| debit_card_specializing | 14 | 12 | 4 | 30 |
| european_football_2 | 14 | 25 | 12 | 51 |
| financial | 3 | 22 | 7 | 32 |
| formula_1 | 28 | 26 | 12 | 66 |
| student_club | 21 | 22 | 5 | 48 |
| superhero | 14 | 26 | 12 | 52 |
| thrombosis_prediction | 7 | 27 | 16 | 50 |
| toxicology | 5 | 17 | 18 | 40 |
| TOTAL | 148 | 250 | 102 | 500 |
</details>
<br>

Each entry in the benchmark looks like this:
```json
  {
    "question_id": 1505,
    "db_id": "debit_card_specializing",
    "question": "Among the customers who paid in euro, how many of them have a monthly consumption of over 1000?",
    "evidence": "Pays in euro = Currency = 'EUR'.",
    "SQL": "SELECT COUNT(*) FROM yearmonth AS T1 INNER JOIN customers AS T2 ON T1.CustomerID = T2.CustomerID WHERE T2.Currency = 'EUR' AND T1.Consumption > 1000.00",
    "difficulty": "simple"
  }
```
- Each question has a unique `question_id`, a `db_id` linking it to a specific database, and a ground truth `SQL` query.
- There's also an `evidence` field - external knowledge that can be optionally used to help an agent map domain-specific language to the right database values.
- And questions are labeled with a `difficulty` rating (simple, moderate, challenging) based on the complexity of the gold SQL query.

### Converting SQL databases to RDF KGs

We converted each SQLite database into an RDF knowledge graph using:
- [RML](https://rml.io/specs/rml/) (RDF Mapping Language) file  - to define how to map relational data to RDF triples, and
- [morph-kgc](https://morph-kgc.readthedocs.io/en/stable/) - the execution engine that reads that RML file and the SQLite database and generates the RDF triples.

The result for each database is a `.nt` file (N-Triples serialization), which was then loaded into a dedicated QLever endpoint for SPARQL querying. Across the 11 databases with 75 tables in total, the resulting knowledge graphs ranged in sizefrom 110 MB to 1.64 GB in N-Triples format.

![morph-kgc](img/morph-kgc.png)

<details>
<summary> Background on RML </summary>
The most basic structure of an RML mapping file is a **Triples Map**. Each Triples Map connects a data source to a pattern for generating RDF triples, and contains three parts:
- a **logical source** (where to get the data from, how to access/iterate)
- a **subject map** (templates for generating IRIs for the subject)
- one or more **predicate-object maps**

```t
# RML mapping file example
@prefix rr: <http://www.w3.org/ns/r2rml#> .
@prefix rml: <http://semweb.mmlab.be/ns/rml#> .
@prefix ql: <http://semweb.mmlab.be/ns/ql#> .
@prefix ex: <http://example.com/ns#> .

<#TriplesMap>
    rml:logicalSource [
        rml:source "db.sqlite" ;                   # Or a table name, CSV, JSON, etc.
        rml:referenceFormulation ql:SQL ;          # Or ql:CSV, ql:JSONPath, etc.
    ] ;
    rr:subjectMap [
        rr:template "http://example.com/{ID}" ;   # How to construct the triple subject
        rr:class ex:Entity ;                      # Optional: class/type of subject
    ] ;
    rr:predicateObjectMap [
        rr:predicate ex:hasAttribute ;
        rr:objectMap [ rml:reference "Value" ] ;  # Or rr:column/rr:constant/rr:template, etc.
    ] .
```

[Here](https://github.com/surbhi-nair/rel-vs-rdf-qa/blob/main/experiments/bird_minidev/european_football_2/european_football_2.rml.ttl)'s one of the RML files we wrote for one of the databases for reference.

</details>
<br>
We produced two versions of each knowledge graph - an auto-generated generic one and a semantic one.

#### Converting to Generic RDF
A simple script reads the SQLite schema via `PRAGMA table_info` and `PRAGMA foreign_key_list` and mechanically generates one Triples Map per table. For each table it:
- Creates a subject IRI using the pattern `http://{db_id}.org/{table}/pk={pkvalue}`
- Adds an `rdfs:label` of the form `"tablename {pk_value}"`
- Maps every column as a literal predicate: `<http://{db_id}.org/{table}#{column_name}>`
- For every declared foreign key, adds a second predicate `ref-{column_name}` that generates a link IRI to the target table's row

**Data Sanitization for Conversion:**

The generic mapping script had to include a few fixes to handle data quality issues in the original databases that would have caused problems in generating valid RDF:
- Predicate local names must not start with a digit: Column names like `2013-14 CALPADS Fall 1 Certification Status` when sanitized to a URI local name still start with a digit, which is invalid in Turtle/N-Triples. Any sanitized local name starting with a digit gets prefixed with `col_` in our script.
- Sanitize special characters in predicate names: Column names had spaces (e.g. `Percent (%) Eligible Free (K-12)`) which were breaking the morph-kgc RDF conversion pipeline repeatedly. So to handle all special characters, we replace all non-alphanumeric characters in column names with underscores and consecutive underscores are collapsed.
- String sanitization: Text values containing double quotes were sanitized and newlines replaced with space to avoid breaking the pipeline. A value like `"Traditional"` (with quotes in the data) would serialize as `""Traditional""`. QLever's parser sees the first `"` as the start of the literal, then the next `"` as closing it so the rest becomes unparseable. 
- Post conversion sanity-check: We did a simple verification to check that the number of subjects per class in the RDF matched the row counts in the SQL tables.

#### Converting to Semantic RDF
The generic mapping faithfully converts the relational structure into RDF, but we also wanted to experiment with a semantically enriched version that allows us to add domain knowledge and produce a cleaner RDF model. This is the version we used for the main comparison while the generic versions were used for an ablation study to see how much of a difference the semantic enrichment made.

The semantic RDF mappings also follow the relational structure of the original SQL databases as closely as possible but with a set of adjustments:
- Human-readable predicates -  The generic mapping generates predicates that mirror the raw column name: `<http://superhero.org/superhero#eye_colour_id>`. The semantic mapping gives them more meaningful names: `hero:hasEyeColour`,`fin:forClient`, `throm:forPatient`, `tox:partOfMolecule`. 
- The float IRI problem - morph-kgc uses Python's `sqlite3` adapter internally to execute the `rml:query` against the SQLite database. Nullable integer columns get returned as `float` objects by this `sqlite3` adapter so when morph-kgc builds IRIs for these, it ends up with IRIs like `<http://superhero.org/superhero/1.0` instead of `<http://superhero.org/superhero/1>`. We have to explicitly cast these to strings in the SQL query to avoid this issue. This fix was also applied to the generic mapping as it is a data quality issue that affects both versions.
```
RML template {superhero id}
→ morph-kgc executes SQL via Python sqlite3
→ sqlite3 returns 1.0 (float)
→ morph-kgc interpolates into IRI → http://superhero.org/superhero/1.0
```
- Typed literals - Semantic mappings use rr:datatype xsd:integer, xsd:date, xsd:decimal on relevant columns.
- Semantic enrichment via RDFS comments - Moving to RDF lets us attach human-readable metadata to schema elements. We encoded BIRD's domain explanations as `rdfs:comment` annotations on properties. 
```t
ef:attacking_work_rate rdfs:comment "high: implies that the player is going to be in all of your attack moves; medium: implies that the player will select the attack actions he will join in; low: remain in his position while the team attacks" .
```
- Boolean and coded values - Some columns stored boolean or categorical data as raw integers. A direct mapping would expose these as bare numeric literals, making them opaque to any agent trying to match human-readable values. We decoded them explicitly in the mappings: `CASE Magnet WHEN 1 THEN 'Yes' WHEN 0 THEN 'No' ELSE 'Unknown' END AS magnet_status`


Here's a basic example for reference - how the same row would appear across the two mappings. The generic mapping on the left and the semantic mapping on the right:
![generic-vs-semantic](img/mappings.png)


### The Contenders
#### Text2SPARQL: GRASP
[GRASP](https://github.com/ad-freiburg/grasp)(Generic Reasoning And SPARQL Generation across Knowledge Graphs) is the Text2SPARQL system used as the SPARQL contender in this comparison. It takes a natural language question and a SPARQL endpoint and finds the answer through iterative exploration. It maintains two pre-built search indices over the knowledge graph - a prefix-keyword index for entity lookup and a vector similarity index for property search - and uses an LLM to explore the graph via functions, observe the result, reason about what to try next and repeat until it has a working query.


#### Text2SQL: CHESS
Our criteria for the Text2SQL agent were:
- Open-source and well-documented
- Has a strong benchmarked performance on the BIRD leaderboard
- Architecturally as similar as possible to GRASP
- Runnable without fundamental modifications to the agent codebase (e.g. no need to change the underlying prompting or reasoning structure or perform training or fine-tuning)

[CHESS](https://github.com/ShayanTalaei/CHESS)(Contextual Harnessing for Efficient SQL Synthesis) is the strongest reasonable SQL baseline on the BIRD leaderboard that closely meets our criteria. It ranks among the top open-source methods on the leaderboard with an upper bound of 71.10% accuracy on the BIRD test set while requiring approximately 83% fewer LLM calls.

![chess-architecture](img/chess-sql.png)[^1]

It runs as a sequential pipeline of four agents:
- Information Retriever (IR): fetches relevant schema context and data values using locality-sensitive hashing and vector similarity search over database catalogs.
- Schema Selector (SS): prunes the full schema down to the tables and columns relevant to the question, reducing token usage by up to 5× while preserving accuracy.
- Candidate Generator (CG): generates SQL using the pruned schema and retrieved context, executes it, and revises on errors or empty results.
- Unit Tester (UT): validates the final candidate by generating natural language unit tests and scoring the query against them, selecting the highest-scoring output as the final answer.

**Similarities with GRASP**

Both systems decompose the problem the same way - find the right schema elements and values, then generate and iteratively refine a query using execution feedback:
| Component | CHESS | GRASP |
|---|---|---|
| Data value/Entity search | LSH index + vector similarity (IR agent) | Prefix-keyword index |
| Schema/property search | Vector DB over catalog (IR agent) | Similarity index via FAISS |
| Query generation | LLM with retrieved context (CG agent) | LLM with retrieved IRIs/triples (exploration loop) |
| Execution feedback | CG revises on syntax error or empty result | `execute` returns results/errors, LLM reasons on them |
| Self-correction | Unit Tester (post-generation) | Built into the exploration loop |

**How the two systems differ**

The difference is *when* the retrieval happens. CHESS front-loads it: IR and SS run before CG touches the schema. GRASP interleaves retrieval and generation. CHESS arrives at query generation with a fully assembled, static picture of the relevant database. GRASP starts with a blank slate and figures it out as it goes. 

Despite this difference in execution flow, CHESS was still the closest structural match to GRASP given our criteria and the available options on the BIRD leaderboard. It is open-source, well-documented, already benchmarked on BIRD with a strong accuracy/cost tradeoff, and architecturally similar enough to GRASP to allow for a fair comparison without needing to modify the underlying agent codebases.

So, finally for our setup, we have something like this. The two systems are given the same question and the same evidence (where applicable), and we compare their outputs using the same evaluation metrics. What those metrics are, and how we designed them to be fair to both systems, is the next section.

![pipeline](img/pipeline.png)

## Evaluation Setup
### What does the BIRD benchmark use?

**Execution Accuracy**: The simplest metric BIRD defines is execution accuracy - does the predicted query return the exact same result set as the gold query when executed against the database? This is a binary metric - either 100% if the sets match exactly, or 0% if they don't.

**Soft F1 Score**: BIRD Mini-dev also defines a more lenient metric. The [Soft F1 score](https://github.com/bird-bench/mini_dev?tab=readme-ov-file#soft-f1-score) is a more lenient alternative to execution accuracy. Instead of asking whether the result sets are identical, it measures how close the predicted result is to the ground truth at the value level - computing precision and recall over matched cell values, then combining into an F1 score.

But, this metric still has limitations when applied to outputs we were getting from GRASP:
- Extra columns penalized: GRASP frequently returns additional columns alongside the answer - labels, related properties, or contextual information that the KG naturally surfaces. The BIRD metric treats any value in the prediction that has no counterpart in the ground truth as a false positive, penalizing GRASP for being more informative.
    ```
    Gold SQL output:            SPARQL output:
    CustomerID                  customer / customerLabel / totalConsumption
    ----------                  ----------------------------------------
    47273                       http://debitcard.org/customer/47273
                                "Customer 47273 (LAM)"
                                0.74
    ```
    So, we propose to not penalise extra columns in the predicted output.
- Row order sensitivity: Soft F1 score aligns rows positionally - row 1 of the prediction against row 1 of the ground truth regardless of whether the question requires ordered results. Outputs that return the same values but in a different order get penalized. Consider this example:
    ```
    Gold SQL output:       Predicted output:
    Time                   time
    --------               --------
    14:29:00               11:55:00   ← same values,
    11:55:00               14:29:00   ← different order
    ```
    So, we propose to have a greedy best-match when no `ORDER BY` is present in the gold SQL else fall back to enforce positional alignment. 
- Float Handling: Soft F1 compares raw values as-is. Relaxed F1 rounds floats to 2 decimal places before comparison

So, we implemented two versions of the F1 score for our evaluation:
- Soft F1 score - the original metric as defined by BIRD
- Relaxed F1 score - a modified version with the above adjustments

<details>
<summary>Example showing the difference in scoring</summary>

**Gold output:**
| CustomerID | Amount |
|---|---|
| 101 | 500 |
| 102 | 300 |

**Predicted output (extra column, extra row):**
| CustomerID | Amount | Label |
|---|---|---|
| 101 | 500 | "Customer A" |
| 102 | 300 | "Customer B" |
| 103 | 200 | "Customer C" |

**Execution accuracy**:

```python
set(predicted) = {(102, 300, "Customer B"), (101, 500, "Customer A"), (103, 200, "Customer C")}
set(gold)      = {(101, 500), (102, 300)}
```
Score = 0

**Soft F1 score**:

| Matched | Predicted_only | Gold_only |
|---|---|---|
| 2/2 = 1 | 1/2 = 0.5 | 0 |
| 2/2 = 1 | 1/2 = 0.5 | 0 |
```
tp = 1 + 1    = 2
fp = 0.5 + 0.5 + 1 = 2
fn = 0

precision = 2 / (2 + 2) = 0.5
recall    = 2 / (2 + 0) = 1
F1        = 2 * 0.5 * 1 / (0.5 + 1) = 0.667

* as per the BIRD implementation, the values are normalised by dividing by the #columns in the gold output
* extra rows in predicted output: 1
```
**Relaxed F1 score**:

| Matched | Predicted_only | Gold_only | | 
|---|---|---|---| 
| 2/2 = 1 | X | 0 | best row match for row 1 of gold output |
| 2/2 = 1 | X | 0 | best row match for row 2 of gold output |
```
tp = 1 + 1 = 2
fp = 1 (extra row in predicted output)
fn = 0

precision = 2 / (2 + 1) = 0.667
recall    = 2 / (2 + 0) = 1
F1        = 2 * 0.667 * 1 / (0.667 + 1) = 0.8
```
So, the relaxed F1 score ends up giving a higher score than the BIRD's Soft F1 score and only penalises for the extra row.

</details>
<br>

### LLM-as-Judge Evaluation

Script-based metrics compare output values mechanically and can miss edge cases, but more importantly they also don't have the ability to reason and understand whether an answer is correct in the context of the question asked. To complement the F1 evaluation, we used **GPT-5-mini** as a judge with two separate evaluation setups:

- with ground truth output - to evaluate correctness with respect to the gold answer
- without ground truth output - to evaluate the agreement between the CHESS and GRASP outputs and to see which answer a real user would prefer based on criteria like plausibility, utility, and confidence

#### With ground truth output: Accuracy Judge

*Is each system's answer correct with respect to the ground truth?*

The judge evaluates CHESS and GRASP outputs, comparing them to the ground truth, classifying each as `CORRECT`, `WRONG_ANSWER`, or `EXECUTION_ERROR`.

The judge is instructed to focus on semantic equivalence, not syntactic similarity - treating rows as unordered sets unless ordering is required, and allowing extra columns in SPARQL output as long as the correct answer is present. Result sets exceeding 30 rows are truncated to the first and last 5, with the total count always provided.

The judge is also asked to categorize the incorrect GRASP answers further as:
- Logical Error: These are the cases where judge identifies the logic of the SPARQL query to not match with that of the gold query. So the predicates and relationships in the query are plausible but there could be issues like wrong filtering, wrong aggregation granularity, wrong relationship direction, etc. that make the answer wrong.
- Non-Logical Error: These are the cases where the judge is not able to find such a mistake in the query logic in comparison to the gold query logic, yet the SPARQL query still returns the wrong result — typically an empty or zero result. This typically happened with cases where the query assumes a predicate or graph structure that is not actually present in the KG. 

**Example for Logical Error:**

> Question: Does the KSV Cercle Brugge team have a slow, balanced or fast speed class?
```sql
-- Gold SQL query:
SELECT DISTINCT t1.buildUpPlaySpeedClass FROM Team_Attributes AS t1 INNER JOIN Team AS t2 
ON t1.team_api_id = t2.team_api_id WHERE t2.team_long_name = 'KSV Cercle Brugge'

-- SPARQL query:
PREFIX ef: <http://europeanfootball.org/schema#>
SELECT ?attr ?label ?speed ( xsd:dateTime ( STRBEFORE( STRAFTER( ?label , \"(\" ) , \")\" ) ) AS ?date ) WHERE {
    ?attr ef:forTeam <http://europeanfootball.org/team/9984> .
    ?attr ef:buildUpPlaySpeedClass ?speed .  
    ?attr rdfs:label ?label .
    } 
ORDER BY DESC ( ?date )
LIMIT 1
```
The gold SQL selects DISTINCT `buildUpPlaySpeedClass` across all historical attribute records for that team, returning two values: Balanced and Fast. The SPARQL query correctly navigates to the same team and the same attribute, but then parses a date out of each attribute's label, orders by it descending, and applies `LIMIT 1` — returning only Balanced, the most recent record. The predicates and the graph traversal is right, but the gold query does not have any date filtering that the SPARQL query has.

**Example for Non-Logical Error:**

> Question: Based on the total cost for all event, what is the percentage of cost for Yearly Kickoff event?
```sql
-- Gold SQL query:
SELECT CAST(SUM(CASE WHEN T1.event_name = 'Yearly Kickoff' THEN T3.cost ELSE 0 END) AS REAL) * 100 / SUM(T3.cost) 
FROM event AS T1 INNER JOIN budget AS T2 ON T1.event_id = T2.link_to_event 
                 INNER JOIN expense AS T3 ON T2.budget_id = T3.link_to_budget
-- outputs 21.53


-- SPARQL query:
PREFIX sclub: <http://studentclub.org/schema#>
SELECT ?kickoffEvent ?kickoffCost ?totalCost ?percent WHERE {  
    {
        SELECT ( SUM( ?kc ) AS ?kickoffCost ) ( SAMPLE( ?ke ) AS ?kickoffEvent ) WHERE {
            ?ke a sclub:Event ; sclub:eventName \"Yearly Kickoff\" ; sclub:cost ?kc . }
    }
    {
        SELECT ( SUM( ?tc ) AS ?totalCost ) WHERE {
            ?ev a sclub:Event ; sclub:cost ?tc . }
    }
    BIND( IF( ?totalCost > 0 , ( ?kickoffCost / ?totalCost ) * 100 , 0 ) AS ?percent )}
-- outputs 0
```
The gold query joins 3 tables (`event` → `budget` → `expense`) and sums costs from the `expense` table. The same structure exists in the knowledge graph as well but the SPARQL query sums `sclub:cost` directly off the `event` node itself. The judge compares the logic of the two queries and reasons that considering the empty set and the wrong traversal, this is a non-logical error. Checking the KG confirms that it follows the same structure as the SQL database and does not have `sclub:cost` directly on the event node, which is why the SPARQL query returns 0.

<details>
<summary>Judge Evaluation Sample Output</summary>
Here is an example from our judge evaluation results:

>Question: "Which was Lewis Hamilton's first race? What were his points recorded for his first race event?"

```json
"sql_eval": {
    "reasoning": "Returns race = 'Malaysian Grand Prix' which matches the 
                  gold. However, returns points = 8.0 while gold returns 
                  14.0. CHESS used the results table rather than 
                  driverStandings, yielding a different points metric.",
    "status": "WRONG_ANSWER"
},
"sparql_eval": {
    "reasoning": "Returns 'Malaysian Grand Prix (2007)' and points = 14.0, 
                  matching the gold exactly. Extra fields (race URI, date, 
                  label) are allowed. Logic is correct.",
    "status": "CORRECT",
    "error_category": "NONE"
},
"comparison": {
    "winner": "SPARQL"
}
```
Both systems returned the right race `name`. CHESS queried the wrong table for `points` and got a different number. The F1 score would have given CHESS partial credit for the matching race name. The judge doesn't. The judge correctly identifies the distinction - and notably, it also explains *why* CHESS was wrong, which is valuable for error analysis.
</details>
<br>

#### Without ground truth output
Here, the ground truth is removed entirely. The judge sees only the question, the SQL output (labelled Agent A), and the SPARQL output (labelled Agent B) and evaluates four dimensions:

| Dimension | Question asked |
|---|---|
| Consistency | Do the two agents agree? |
| Plausibility | Does the output logically answer the question? |
| Utility | Which output is easier for a human to read and act on? |
| Confidence | Which output feels more credible based on its data distribution? |

The consensus status is picked between either `FULL_AGREEMENT`, `PARTIAL_AGREEMENT`, or `TOTAL_DISAGREEMENT` while plausibility and utility are given as brief reasoning statements. The judge then picks a winner - `AGENT_A`, `AGENT_B`, or `TIE` - with a confidence score from 1 to 10.

This metric tries to answer:
- how much do the two systems actually agree with each other when we remove the ground truth as a reference point?
- if a user received these two responses, which one would they prefer?

This could surface cases where both could be defensibly correct or where the definition of a correct answer is ambiguous. We will look into a few of those cases in the later sections.


## Results
### Accuracy Results
#### F1 Score
| | Soft F1 | Relaxed F1 |
|---|---|---|
| SQL | 65.23% | 70.08% |
| SPARQL | 22.38% | 46.64% |

The soft F1 gap looks large - 42.85 percentage points. The relaxed F1 narrows this to 23.44 points. Even so, CHESS leads the accuracy evaluation according to the F1 score. 

#### LLM Judge
||||
|---|---|---|
| | SPARQL CORRECT | SPARQL INCORRECT |
| SQL CORRECT | 49.6% | 16.8% |
| SQL INCORRECT | 6% | 27.6% |

- CHESS is correct on 66.4% of questions, GRASP on 55.6%.
- Both get it right on 49.6% of questions - nearly half the benchmark.
- CHESS exclusively beats GRASP on 16.8% of questions, GRASP exclusively beats CHESS on just 6%.
- 27.6% of questions are wrong for both systems which is a reminder that the benchmark is genuinely hard and that there are many questions that neither approach can currently handle.
- The accuracy gap here (10.8 percentage points) is much smaller than the Soft F1 gap (42.85 points) would suggest which validates that the BIRD's Soft F1 metric is not fully capturing the correctness in the GRASP outputs.

**By Difficulty**
| Difficulty | CHESS | GRASP | Gap |
|---|---|---|---|
| Simple | 76.35% | 64.18% | 12.17 |
| Moderate | 64.4% | 52.4% | 12 |
| Challenging | 56.86% | 50.98% | 5.88 |

- Out of all the simple questions, CHESS got 76.35% correct while GRASP got 64.18% correct, giving a gap of 12.17 percentage points.
- The gap nearly halves on challenging questions where both systems seem to struggle more equally. Since the difficulty levels are not evenly distributed across databases we also look at the breakdown by database to see if there are specific schemas where GRASP is doing better or worse than CHESS.

**By Database**
| Database | CHESS | GRASP | Gap | 
|---|---|---|---|
| superhero | 78.8% | **82.7%** | 3.9 |
| student_club | 79.2% | 70.8% | 8.4 |
| formula_1 | 75.8% | 69.7% | 6.1 |
| european_football_2 | 68.6% | 62.7% | 5.9 |
| toxicology | 70.0% | 57.5% | 12.5 |
| codebase_community | 69.4% | 51.0% | 18.4 |
| thrombosis_prediction | 50.0% | 50.0% | 0 |
| debit_card_specializing | 60.0% | 43.3% | 16.7 |
| california_schools | 56.7% | 33.3% | 23.4 |
| financial | 56.3% | 37.5% | 18.8 |
| card_games | 53.8% | 28.8% | 25.0 |

<details>
<summary>Complete Breakdown By Database</summary>

| db_id | only SPARQL correct | only SQL correct | BOTH_CORRECT | BOTH_INCORRECT | total questions |
|-------|-----------|-------|---------|-----------|------|
| california_schools | 2 | 9 | 8 | 11  | 30 |
| card_games | 5 | 18| 10| 19  | 52 |
| codebase_community | 1 | 10| 24| 14  | 49 |
| debit_card_specializing | 0 | 5 | 13| 12  | 30 |
| european_football_2| 2 | 5 | 30| 14  | 51 |
| financial | 1 | 7 | 11| 13  | 32 |
| formula_1 | 2 | 6 | 44| 14  | 66 |
| student_club | 2 | 6 | 32| 8| 48  |
| superhero | 7 | 5 | 36| 4| 52  |
| thrombosis_prediction| 5 | 5 | 20| 20  | 50  |
| toxicology | 3 | 8 | 20| 9| 40  |
</details>
<br>

- `superhero` is the only database where GRASP outperforms CHESS. It also has the fewest both-wrong cases (4 out of 52). `formula_1` is also a strong database for GRASP. Both of these have a clean, well-normalized schema with simple, self-describing fields. `superhero` has lookup tables like alignment, colour, gender, race, publisher with clearer relationships. `formula_1` has drivers, races, results etc. which are easy to understand and link together.
- `card_games`, `california_schools` and `financial` - both agents perform poorly on these compared to other databases but these are also GRASP's worst databases with the most performance gap.
- `thrombosis_prediction` is the only database where both systems are exactly tied, but it also has one of the highest rates of both-incorrect cases (where both systems gave wrong answers). We could note that only 14% of the questions of this database are simple, the rest are moderate or challenging so the benchmark already categorizes it as a harder database. But `toxicology` has an even higher proportion of challenging questions (45%) yet both systems score better on it, suggesting that difficulty label alone doesn't explain thrombosis's low scores.

**GRASP Error Breakdown**

Out of the 222 questions that GRASP got wrong:
- 162 were Logical Errors - core logic of SPARQL query deviates from that of the gold query, such as wrong filtering, wrong aggregation etc.
- 60 were Non-Logical Errors - judge couldn't identify a logical mistake in the query but it still returned the wrong answer, typically due to structural mismatch(wrong predicate or graph structure assumed)

The distribution of errors is not uniform across databases. Out of the total questions for a given database, the percentage of questions with each error type varies as:

| Database | Correct | Logical Error | Non-Logical Error |
|---|---|---|---|
| superhero | 83% | 13% | 4% |
| student_club | 71% | 21% | 8% |
| formula_1 | 70% | 27% | 3% |
| european_football_2 | 63% | 33% | 4% |
| toxicology | 57% | 40% | 2% |
| codebase_community | 51% | 41% | 8% |
| thrombosis_prediction | 50% | 34% | 16% |
| debit_card_specializing | 43% | 43% | 13% |
| financial | 38% | 47% | 16% |
| california_schools | 33% | 33% | 33% |
| card_games | 29% | 35% | 35% |

- `superhero` and `formula_1` have high accuracy coupled with the lowest non-logical error rates(least structural mismatch). This could be because they are well-normalized with meaningful, clean fields. `superhero` has 10 tables largely organised around clean, lookup relationships. `formula_1` has 13 tables with self-explanatory names (drivers, races, results, constructors). In these databases, GRASP can largely infer the right predicates because the column names directly suggest what they are. Almost all of GRASP's errors in these databases are logic errors (wrong aggregation, wrong filter).
- `card_games` and `california_schools` have the highest error rates with GRASP
    - `california_schools`: The `frpm` table has 27 column names with spaces, parentheses, and special characters like "Percent (%) Eligible Free (K-12)", "Charter School (Y/N)", "2013-14 CALPADS Fall 1 Certification Status". These were simplified in the semantic RDF mapping but depending on the question, the LLM might have still struggled to match the right property. It also has similar column names across different tables which could have added to the confusion - for example, `County`, `District`, `Street` appear in two tables each.
    - `card_games`: The main `cards` table alone has 74 columns with plausible-sounding names like `cardKingdomFoilId`, `cardKingdomId`, `mtgoId`, `mtgoFoilId`. Despite adding `rdfs:comment` annotations to clarify these in the semantic mapping, the LLM might have still struggled.
- `thrombosis_prediction` is an outlier case with zero performance gap between CHESS and GRASP. CHESS performs the worst on it but GRASP instead has other databases where it performs much worse than it does on this one. Looking at the database, it has specific medical-laboratory jargon in its column names which could be difficult to match. The other databases where GRASP performs poorly may not have the same level of jargon but they still have confusing column names so the reason for this outlier performance is not something we can fully attribute to any specific factor conclusively.

Looking across the databases, no single schema property cleanly predicts where GRASP struggles or succeeds. Error rates were higher in databases with opaque or confusing column naming, and a large number of columns(`card_games`, `california_schools`). Domain-specific jargon usage in columns could also be a factor. But databases with similar structural characteristics don't always produce similar results - `thrombosis_prediction` and `toxicology` both have comparatively complex domain-specific terminology, yet perform differently for both systems. Beyond the observations already noted, the per-database variation was hard to attribute to any single factor.

Adding the set of questions from one database, where GRASP got it wrong, for reference:
<details>
<summary>Toxicology database - cases where both got it wrong</summary>

Here are the questions from the `toxicology` database where both agents got it wrong.

<details>
<summary>QID 207 — What elements are in a double type bond? <code>challenging</code></summary>

**Question:** What elements are in a double type bond?

**Gold SQL**
```sql
SELECT DISTINCT T1.element
FROM atom AS T1
INNER JOIN bond AS T2 ON T1.molecule_id = T2.molecule_id
INNER JOIN connected AS T3 ON T1.atom_id = T3.atom_id
WHERE T2.bond_type = '='
```

**Gold Output**
| element |
|---|
| c |
| o |
| cl |
| h |
| s |
| n |
| p |
| f |
| sn |
| pb |
| ca |
| br |
| cu |

**Predicted SQL**
```sql
SELECT DISTINCT a.element
FROM connected AS c
INNER JOIN bond AS b ON c.bond_id = b.bond_id
INNER JOIN atom AS a ON (a.atom_id = c.atom_id OR a.atom_id = c.atom_id2)
WHERE b.bond_type = '='
```

**Predicted SQL Output**
| element |
|---|
| c |
| o |
| n |
| s |
| ca |

**Predicted SPARQL**
```sparql
PREFIX tox: <http://toxkg.org/schema#>
SELECT DISTINCT ?element WHERE {
  ?bond tox:bondType "=" .
  ?bond tox:connectsAtom ?atom .
  ?atom tox:element ?element .
}
ORDER BY ?element
```

**Predicted SPARQL Output**
| element |
|---|
| Calcium |
| Carbon |
| Nitrogen |
| Oxygen |
| Sulfur |

</details>

---


<details>
<summary>QID 219 — Percentage of carcinogenic molecules in triple type bonds <code>challenging</code></summary>

**Question:** What is the percentage of carcinogenic molecules in triple type bonds?

**Gold SQL**
```sql
SELECT CAST(COUNT(DISTINCT CASE WHEN T2.label = '+' THEN T2.molecule_id ELSE NULL END) AS REAL)
  * 100 / COUNT(DISTINCT T2.molecule_id)
FROM atom AS T1
INNER JOIN molecule AS T2 ON T1.molecule_id = T2.molecule_id
INNER JOIN bond AS T3 ON T2.molecule_id = T3.molecule_id
WHERE T3.bond_type = '#'
```

**Gold Output**
| percentage |
|---|
| 66.6667 |

**Predicted SQL**
```sql
SELECT CASE WHEN COUNT(b.bond_id) = 0 THEN 0
  ELSE (SUM(CASE WHEN b.bond_type = '#' THEN 1 ELSE 0 END) * 100.0) / COUNT(b.bond_id) END AS percent
FROM bond AS b
INNER JOIN molecule AS m ON b.molecule_id = m.molecule_id
WHERE m.label = '+'
```

**Predicted SQL Output**
| percent |
|---|
| 0.0808 |

**Predicted SPARQL**
```sparql
PREFIX tox: <http://toxkg.org/schema#>
SELECT
  ( ( SUM( IF( str( ?bondType ) = "#" , 1 , 0 ) ) * 100.0 ) / COUNT( ?bond ) AS ?percent )
  ( COUNT( ?bond ) AS ?totalBonds )
  ( SUM( IF( str( ?bondType ) = "#" , 1 , 0 ) ) AS ?tripleBonds )
WHERE {
  ?bond a tox:Bond ; tox:partOfMolecule ?mol ; tox:bondType ?bondType .
  ?mol tox:hasCarcinogenicity "Carcinogenic" .
}
```

**Predicted SPARQL Output**
| percent | totalBonds | tripleBonds |
|---|---|---|
| 0.0808 | 3715 | 3 |

</details>

---

<details>
<summary>QID 234 — How many bonds involving atom 12 does molecule TR009 have? <code>moderate</code></summary>

**Question:** How many bonds which involved atom 12 does molecule TR009 have?

**Gold SQL**
```sql
SELECT COUNT(T2.bond_id)
FROM bond AS T1
INNER JOIN connected AS T2 ON T1.bond_id = T2.bond_id
WHERE T1.molecule_id = 'TR009'
AND T2.atom_id = T1.molecule_id || '_1'
OR T2.atom_id2 = T1.molecule_id || '_2'
```

**Gold Output**
| COUNT(bond_id) |
|---|
| 1041 |

**Predicted SQL**
```sql
SELECT COUNT(DISTINCT T1.bond_id)
FROM connected AS T1
INNER JOIN bond AS T2 ON T1.bond_id = T2.bond_id
WHERE T2.molecule_id = 'TR009'
AND (T1.atom_id = 'TR009_12' OR T1.atom_id2 = 'TR009_12')
```

**Predicted SQL Output**
| COUNT(DISTINCT bond_id) |
|---|
| 3 |

**Predicted SPARQL**
```sparql
PREFIX tox: <http://toxkg.org/schema#>
SELECT ( COUNT( DISTINCT ?bond ) AS ?bondCount ) ?molecule ?atom WHERE {
  BIND( <http://toxkg.org/molecule/TR009> AS ?molecule )
  BIND( <http://toxkg.org/atom/TR009_12> AS ?atom )
  ?bond tox:connectsAtom ?atom ; tox:partOfMolecule ?molecule .
}
GROUP BY ?molecule ?atom
```

**Predicted SPARQL Output**
| bondCount | molecule | atom |
|---|---|---|
| 3 | http://toxkg.org/molecule/TR009 | http://toxkg.org/atom/TR009_12 |

</details>

---

<details>
<summary>QID 281 — Tally elements of the 4th atom of each carcinogenic molecule <code>challenging</code></summary>

**Question:** Tally the toxicology element of the 4th atom of each molecule that was carcinogenic.

**Gold SQL**
```sql
SELECT DISTINCT T1.element
FROM atom AS T1
INNER JOIN molecule AS T2 ON T1.molecule_id = T2.molecule_id
WHERE T2.label = '+' AND SUBSTR(T1.atom_id, -1) = '4' AND LENGTH(T1.atom_id) = 7
```

**Gold Output**
| element |
|---|
| cl |
| c |
| br |
| n |
| o |
| s |
| h |
| f |

**Predicted SQL**
```sql
SELECT a.element, COUNT(*) AS tally
FROM atom AS a
INNER JOIN molecule AS m ON a.molecule_id = m.molecule_id
WHERE m.label = '+' AND SUBSTR(a.atom_id, 7, 1) = '4'
GROUP BY a.element
ORDER BY COUNT(*) DESC
```

**Predicted SQL Output**
| element | tally |
|---|---|
| c | 145 |
| h | 59 |
| o | 33 |
| cl | 9 |
| n | 8 |
| br | 6 |
| s | 5 |
| na | 3 |
| f | 1 |

**Predicted SPARQL**
```sparql
PREFIX tox: <http://toxkg.org/schema#>
SELECT ?element ( COUNT( ?atom ) AS ?count ) WHERE {
  ?mol a tox:Molecule ; tox:hasCarcinogenicity ?car .
  FILTER ( str( ?car ) = "Carcinogenic" )
  ?atom a tox:Atom ; tox:partOfMolecule ?mol ; tox:element ?element .
  BIND( STRAFTER( STR( ?atom ) , "/atom/" ) AS ?atom_id )
  FILTER ( substr( ?atom_id , 7 , 1 ) = "4" )
}
GROUP BY ?element
ORDER BY DESC ( ?count )
```

**Predicted SPARQL Output**
| element | count |
|---|---|
| Carbon | 145 |
| Hydrogen | 59 |
| Oxygen | 33 |
| Chlorine | 9 |
| Nitrogen | 8 |
| Bromine | 6 |
| Sulfur | 5 |
| Sodium | 3 |
| Fluorine | 1 |

</details>

---

<details>
<summary>QID 198 — On average how many carcinogenic molecules are single bonded? <code>challenging</code></summary>

**Question:** On average how many carcinogenic molecules are single bonded?

**Gold SQL**
```sql
SELECT AVG(single_bond_count) FROM (
  SELECT T3.molecule_id, COUNT(T1.bond_type) AS single_bond_count
  FROM bond AS T1
  INNER JOIN atom AS T2 ON T1.molecule_id = T2.molecule_id
  INNER JOIN molecule AS T3 ON T3.molecule_id = T2.molecule_id
  WHERE T1.bond_type = '-' AND T3.label = '+'
  GROUP BY T3.molecule_id
) AS subquery
```

**Gold Output**
| AVG(single_bond_count) |
|---|
| 732.125 |

**Predicted SQL**
```sql
SELECT CASE WHEN den.total_atoms = 0 THEN NULL
  ELSE num.single_bonds * 1.0 / den.total_atoms END
FROM (
  SELECT COUNT(*) AS single_bonds FROM bond
  INNER JOIN molecule ON bond.molecule_id = molecule.molecule_id
  WHERE molecule.label = '+' AND bond.bond_type = '-'
) AS num,
(
  SELECT COUNT(atom.atom_id) AS total_atoms FROM atom
  INNER JOIN molecule ON atom.molecule_id = molecule.molecule_id
  WHERE molecule.label = '+'
) AS den
```

**Predicted SQL Output**
| result |
|---|
| 0.8337 |

**Predicted SPARQL**
```sparql
PREFIX tox: <http://toxkg.org/schema#>
PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>
SELECT ( AVG( ?ratio ) AS ?avg_single_per_atom ) WHERE {
  {
    SELECT ?mol ( COUNT( DISTINCT ?bond ) AS ?singleCount ) ( COUNT( DISTINCT ?atom ) AS ?atomCount ) WHERE {
      ?mol tox:hasCarcinogenicity "Carcinogenic" .
      ?atom tox:partOfMolecule ?mol .
      OPTIONAL {
        ?bond tox:connectsAtom ?atom .
        ?bond tox:bondType "-" .
      }
    }
    GROUP BY ?mol
  }
  BIND( IF( ?atomCount > 0 , xsd:decimal( ?singleCount ) / xsd:decimal( ?atomCount ) , 0 ) AS ?ratio )
}
```

**Predicted SPARQL Output**
| avg_single_per_atom |
|---|
| 0.417574 |

</details>

---


<details>
<summary>QID 247 — List elements of atoms that cannot bond with any other atoms <code>challenging</code></summary>

**Question:** List all the elements of atoms that cannot bond with any other atoms.

**Gold SQL**
```sql
SELECT DISTINCT T.element FROM atom AS T
WHERE T.element NOT IN (
  SELECT DISTINCT T1.element FROM atom AS T1
  INNER JOIN connected AS T2 ON T1.atom_id = T2.atom_id
)
```

**Gold Output**
| element |
|---|
| na |
| zn |
| k |

**Predicted SQL**
```sql
SELECT DISTINCT element FROM atom
WHERE atom_id NOT IN (
  SELECT atom_id FROM connected
  UNION
  SELECT atom_id2 FROM connected
)
```

**Predicted SQL Output**
| element |
|---|
| na |
| cl |
| h |
| zn |
| k |

**Predicted SPARQL**
```sparql
PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
PREFIX tox: <http://toxkg.org/schema#>
SELECT DISTINCT ?element WHERE {
  ?atom rdf:type tox:Atom ; tox:element ?element .
  FILTER NOT EXISTS { ?bond tox:connectsAtom ?atom }
}
ORDER BY ?element
```

**Predicted SPARQL Output**
| element |
|---|
| Chlorine |
| Hydrogen |
| Sodium |
| Unknown Element |

</details>

---

<details>
<summary>QID 260 — Total atoms in triple-bond molecules containing phosphorus or bromine <code>moderate</code></summary>

**Question:** Calculate the total atoms with triple-bond molecules containing the element phosphorus or bromine.

**Gold SQL**
```sql
SELECT COUNT(T1.atom_id)
FROM atom AS T1
INNER JOIN molecule AS T2 ON T1.molecule_id = T2.molecule_id
INNER JOIN bond AS T3 ON T2.molecule_id = T3.molecule_id
WHERE T3.bond_type = '#' AND T1.element IN ('p', 'br')
```

**Gold Output**
| COUNT(atom_id) |
|---|
| 1 |

**Predicted SQL**
```sql
SELECT COUNT(a.atom_id) FROM atom AS a
WHERE EXISTS (SELECT 1 FROM bond AS b WHERE b.molecule_id = a.molecule_id AND b.bond_type = '#')
AND EXISTS (SELECT 1 FROM atom AS a2 WHERE a2.molecule_id = a.molecule_id AND a2.element IN ('p','br'))
```

**Predicted SQL Output**
| COUNT(atom_id) |
|---|
| 4 |

**Predicted SPARQL**
```sparql
PREFIX tox: <http://toxkg.org/schema#>
SELECT ( SUM( ?atomCount ) AS ?totalAtoms ) WHERE {
  {
    SELECT ?mol ( COUNT( DISTINCT ?atom ) AS ?atomCount ) WHERE {
      ?b tox:partOfMolecule ?mol ; tox:bondType "#" .
      ?a1 tox:partOfMolecule ?mol ; tox:element ?elem .
      FILTER ( ?elem IN ( "Phosphorus" , "Bromine" ) )
      ?atom tox:partOfMolecule ?mol .
    }
    GROUP BY ?mol
  }
}
```

**Predicted SPARQL Output**
| totalAtoms |
|---|
| 7 |

</details>

---

<details>
<summary>QID 263 — Percentage of chlorine in single bond molecules <code>challenging</code></summary>

**Question:** What is the composition of element chlorine in percentage among the single bond molecules?

**Gold SQL**
```sql
SELECT CAST(COUNT(CASE WHEN T.element = 'cl' THEN T.atom_id ELSE NULL END) AS REAL)
  * 100 / COUNT(T.atom_id)
FROM (
  SELECT T1.atom_id, T1.element FROM atom AS T1
  INNER JOIN molecule AS T2 ON T1.molecule_id = T2.molecule_id
  INNER JOIN bond AS T3 ON T2.molecule_id = T3.molecule_id
  WHERE T3.bond_type = '-'
) AS T
```

**Gold Output**
| percentage |
|---|
| 2.6840 |

**Predicted SQL**
```sql
SELECT (SUM(CASE WHEN element = 'cl' THEN 1 ELSE 0 END) * 100.0) / COUNT(*) AS percent
FROM atom
WHERE molecule_id IN (SELECT molecule_id FROM bond WHERE bond_type = '-')
```

**Predicted SQL Output**
| percent |
|---|
| 3.4824 |

**Predicted SPARQL**
```sparql
PREFIX tox: <http://toxkg.org/schema#>
SELECT
  ( SUM( IF( str( ?element ) = "Chlorine" , 1 , 0 ) ) AS ?num_chlorine )
  ( COUNT( ?atom ) AS ?total_atoms )
  ( ( SUM( IF( str( ?element ) = "Chlorine" , 1 , 0 ) ) / COUNT( ?atom ) ) * 100 AS ?percent )
WHERE {
  ?bond tox:bondType "-" .
  ?bond tox:connectsAtom ?atom .
  ?atom tox:element ?element .
}
```

**Predicted SPARQL Output**
| num_chlorine | total_atoms | percent |
|---|---|---|
| 314 | 15486 | 2.0276 |

</details>

---

---

<details>
<summary>QID 201 — Percentage of carbon in double-bond molecules <code>moderate</code></summary>

**Question:** What is the percentage of carbon in double-bond molecules?

**Gold SQL**
```sql
SELECT CAST(COUNT(DISTINCT CASE WHEN T1.element = 'c' THEN T1.atom_id ELSE NULL END) AS REAL)
  * 100 / COUNT(DISTINCT T1.atom_id)
FROM atom AS T1
INNER JOIN bond AS T2 ON T1.molecule_id = T2.molecule_id
WHERE T2.bond_type = '='
```

**Gold Output**
| percentage |
|---|
| 38.8096 |

**Predicted SQL**
```sql
SELECT (SUM(CASE WHEN T1.element = 'c' THEN 1 ELSE 0 END) * 1.0) / COUNT(T1.atom_id)
FROM atom AS T1
INNER JOIN (SELECT DISTINCT molecule_id FROM bond WHERE bond_type = '=') AS T2
  ON T1.molecule_id = T2.molecule_id
```

**Predicted SQL Output**
| percentage |
|---|
| 0.3881 |

**Predicted SPARQL**
```sparql
PREFIX tox: <http://toxkg.org/schema#>
PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>
SELECT ?carbons ?total ( ( xsd:double( ?carbons ) / xsd:double( ?total ) ) AS ?percentage ) WHERE {
  {
    SELECT ( COUNT( ?atom ) AS ?total ) WHERE {
      ?bond a tox:Bond ; tox:bondType "=" ; tox:partOfMolecule ?mol .
      ?atom tox:partOfMolecule ?mol .
    }
  }
  {
    SELECT ( COUNT( ?carbonAtom ) AS ?carbons ) WHERE {
      ?bond2 a tox:Bond ; tox:bondType "=" ; tox:partOfMolecule ?mol2 .
      ?carbonAtom tox:partOfMolecule ?mol2 ; tox:element ?el .
      FILTER ( lcase( str( ?el ) ) = "carbon" )
    }
  }
}
```

**Predicted SPARQL Output**
| carbons | total | percentage |
|---|---|---|
| 20966 | 102779 | 0.203991 |

</details>


</details>

<br>

<details>
<summary>Toxicology database - cases where only GRASP got it wrong</summary>

Here are all the questions from the `toxicology` database where only GRASP got it wrong:
<details>
<summary>QID 197 — Calculate the average number of oxygen atoms in single-bonded molecules <code>moderate</code></summary>

**Question:** Calculate the average number of oxygen atoms in single-bonded molecules.

**Gold SQL**
```sql
SELECT AVG(oxygen_count) FROM (
  SELECT T1.molecule_id, COUNT(T1.element) AS oxygen_count
  FROM atom AS T1
  INNER JOIN bond AS T2 ON T1.molecule_id = T2.molecule_id
  WHERE T2.bond_type = '-' AND T1.element = 'o'
  GROUP BY T1.molecule_id
) AS oxygen_counts
```

**Gold Output**
| AVG(oxygen_count) |
|---|
| 99.6835 |

**Predicted SPARQL**
```sparql
PREFIX tox: <http://toxkg.org/schema#>
SELECT ( AVG( ?oCount ) AS ?avgOxygenPerSingleBondedMolecule ) WHERE {
  {
    SELECT ?molecule ( COUNT( DISTINCT ?atom ) AS ?oCount ) WHERE {
      ?atom tox:partOfMolecule ?molecule ; tox:element "Oxygen" .
      FILTER NOT EXISTS {
        ?bond tox:partOfMolecule ?molecule ; tox:bondType ?bt .
        FILTER ( ?bt != "-" )
      }
    }
    GROUP BY ?molecule
  }
}
```

**SPARQL Output**
| avgOxygenPerSingleBondedMolecule |
|---|
| 2.30769 |

</details>

---

<details>
<summary>QID 208 — Which type of label is the most numerous in atoms with hydrogen? <code>moderate</code></summary>

**Question:** Which type of label is the most numerous in atoms with hydrogen?

**Gold SQL**
```sql
SELECT T.label FROM (
  SELECT T2.label, COUNT(T2.molecule_id)
  FROM atom AS T1
  INNER JOIN molecule AS T2 ON T1.molecule_id = T2.molecule_id
  WHERE T1.element = 'h'
  GROUP BY T2.label
  ORDER BY COUNT(T2.molecule_id) DESC
  LIMIT 1
) t
```

**Gold Output**
| label |
|---|
| - |

**Predicted SPARQL**
```sparql
PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
PREFIX tox: <http://toxkg.org/schema#>
SELECT ?labelProp ( COUNT( DISTINCT ?atom ) AS ?count ) WHERE {
  ?atom rdf:type tox:Atom ; tox:element "Hydrogen" ; ?labelProp ?labelVal .
  FILTER ( CONTAINS( LCASE( STR( ?labelProp ) ) , "label" ) )
}
GROUP BY ?labelProp
ORDER BY DESC ( ?count )
LIMIT 1
```

**SPARQL Output**
| labelProp | count |
|---|---|
| http://www.w3.org/2000/01/rdf-schema#label | 4034 |

</details>

---

<details>
<summary>QID 220 — List top three elements of molecule TR000 in alphabetical order <code>challenging</code></summary>

**Question:** Please list top three elements of the toxicology of the molecule TR000 in alphabetical order.

**Gold SQL**
```sql
SELECT DISTINCT T.element
FROM atom AS T
WHERE T.molecule_id = 'TR000'
ORDER BY T.element
LIMIT 3
```

**Gold Output**
| element |
|---|
| c |
| cl |
| h |

**Predicted SPARQL**
```sparql
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
PREFIX tox: <http://toxkg.org/schema#>
SELECT ?toxElement ?label WHERE {
  BIND( <http://toxkg.org/molecule/TR000> AS ?molecule )
  ?molecule ?p ?toxElement .
  FILTER ( STRSTARTS( STR( ?p ) , STR( tox: ) ) ) .
  OPTIONAL { ?toxElement rdfs:label ?toxElementLabel . }
  BIND( COALESCE ( STR( ?toxElementLabel ) , STR( ?toxElement ) ) AS ?label )
}
ORDER BY LCASE( ?label )
LIMIT 3
```

**SPARQL Output**
| toxElement | label |
|---|---|
| Carcinogenic | Carcinogenic |

</details>

---

<details>
<summary>QID 228 — Percentage of hydrogen in molecule TR206 to four decimal places <code>moderate</code></summary>

**Question:** How much of the hydrogen in molecule TR206 is accounted for? Please provide your answer as a percentage with four decimal places.

**Gold SQL**
```sql
SELECT ROUND(
  CAST(COUNT(CASE WHEN T.element = 'h' THEN T.atom_id ELSE NULL END) AS REAL)
  * 100 / COUNT(T.atom_id), 4
)
FROM atom AS T
WHERE T.molecule_id = 'TR206'
```

**Gold Output**
| percent |
|---|
| 45.4545 |

**Predicted SPARQL**
```sparql
PREFIX tox: <http://toxkg.org/schema#>
PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>
SELECT ?molecule ?total ?hydrogen ?percentStr WHERE {
  BIND( <http://toxkg.org/molecule/TR206> AS ?molecule )
  { SELECT ( COUNT( ?atom ) AS ?total ) WHERE { ?atom tox:partOfMolecule ?molecule . } }
  {
    SELECT ( COUNT( ?hAtom ) AS ?hydrogen ) WHERE {
      ?hAtom tox:partOfMolecule ?molecule ; tox:element ?el .
      FILTER ( lcase( str( ?el ) ) = "hydrogen" || lcase( str( ?el ) ) = "h" )
    }
  }
  BIND( ( xsd:decimal( ?hydrogen ) * 100.0 ) / xsd:decimal( ?total ) AS ?rawPercent )
  ...
}
```

**SPARQL Output**
| molecule | total | hydrogen | percentStr |
|---|---|---|---|
| http://toxkg.org/molecule/TR206 | 18267 | 4034 | 22.0835 |

</details>

---

<details>
<summary>QID 230 — Elements and label of molecule TR060 <code>challenging</code></summary>

**Question:** What are the elements of the toxicology and label of molecule TR060?

**Gold SQL**
```sql
SELECT DISTINCT T1.element, T2.label
FROM atom AS T1
INNER JOIN molecule AS T2 ON T1.molecule_id = T2.molecule_id
WHERE T2.molecule_id = 'TR060'
```

**Gold Output**
| element | label |
|---|---|
| c | - |
| h | - |
| o | - |
| n | - |
| cl | - |

**Predicted SPARQL**
```sparql
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
PREFIX tox: <http://toxkg.org/schema#>
SELECT ?prop ?propLabel ?obj WHERE {
  BIND( <http://toxkg.org/molecule/TR060> AS ?m )
  ?m ?prop ?obj .
  FILTER ( STRSTARTS( STR( ?prop ) , STR( tox: ) ) || ?prop = rdfs:label )
  OPTIONAL { ?prop rdfs:label ?propLabel . }
}
```

**SPARQL Output**
| prop | propLabel | obj |
|---|---|---|
| http://toxkg.org/schema#hasCarcinogenicity | null | Non-Carcinogenic |
| http://www.w3.org/2000/01/rdf-schema#label | null | Molecule TR060 |

</details>

---

<details>
<summary>QID 239 — How many connections does atom 19 have? <code>simple</code></summary>

**Question:** How many connections does the atom 19 have?

**Gold SQL**
```sql
SELECT COUNT(T.bond_id)
FROM connected AS T
WHERE SUBSTR(T.atom_id, -2) = '19'
```

**Gold Output**
| COUNT(bond_id) |
|---|
| 377 |

**Predicted SPARQL**
```sparql
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
PREFIX tox: <http://toxkg.org/schema#>
SELECT ?atom ( COUNT( DISTINCT ?bond ) AS ?connections ) ?atomLabel WHERE {
  ?bond tox:connectsAtom ?atom .
  FILTER ( regex( str( ?atom ) , "_19$" ) )
  OPTIONAL { ?atom rdfs:label ?atomLabel }
}
GROUP BY ?atom ?atomLabel
ORDER BY DESC ( ?connections )
```

**SPARQL Output** *(219 rows — showing first)*
| atom | connections | atomLabel |
|---|---|---|
| http://toxkg.org/atom/TR186_19 | 4 | Atom TR186_19 (Carbon) |

</details>

---

<details>
<summary>QID 240 — List all elements of molecule TR004 <code>challenging</code></summary>

**Question:** List all the elements of the toxicology of the molecule "TR004".

**Gold SQL**
```sql
SELECT DISTINCT T.element
FROM atom AS T
WHERE T.molecule_id = 'TR004'
```

**Gold Output**
| element |
|---|
| s |
| n |
| o |
| c |
| h |
| p |

**Predicted SPARQL**
```sparql
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
PREFIX tox: <http://toxkg.org/schema#>
SELECT ?p ?o ?o_label WHERE {
  <http://toxkg.org/molecule/TR004> ?p ?o .
  FILTER ( STRSTARTS( STR( ?p ) , STR( tox: ) ) )
  OPTIONAL { ?o rdfs:label ?o_label }
}
ORDER BY ?p
```

**SPARQL Output**
| p | o | o_label |
|---|---|---|
| http://toxkg.org/schema#hasCarcinogenicity | Non-Carcinogenic | null |

</details>

---

<details>
<summary>QID 273 — Percentage of chlorine in carcinogenic molecules <code>moderate</code></summary>

**Question:** What is the percentage of element chlorine in carcinogenic molecules?

**Gold SQL**
```sql
SELECT CAST(COUNT(CASE WHEN T1.element = 'cl' THEN T1.element ELSE NULL END) AS REAL)
  * 100 / COUNT(T1.element)
FROM atom AS T1
INNER JOIN molecule AS T2 ON T1.molecule_id = T2.molecule_id
WHERE T2.label = '+'
```

**Gold Output**
| percentage |
|---|
| 3.1419 |

**Predicted SPARQL**
```sparql
PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
PREFIX tox: <http://toxkg.org/schema#>
SELECT ?percentage ?withCl ?total WHERE {
  {
    SELECT ( COUNT( DISTINCT ?m ) AS ?total ) WHERE {
      ?m rdf:type tox:Molecule ; tox:hasCarcinogenicity "Carcinogenic" .
    }
  }
  {
    SELECT ( COUNT( DISTINCT ?m2 ) AS ?withCl ) WHERE {
      ?m2 rdf:type tox:Molecule ; tox:hasCarcinogenicity "Carcinogenic" .
      ?a tox:partOfMolecule ?m2 ; tox:element "Chlorine" .
    }
  }
  BIND( ( ( ?withCl * 100.0 ) / ?total ) AS ?percentage )
}
```

**SPARQL Output**
| percentage | withCl | total |
|---|---|---|
| 28.9474 | 44 | 152 |

</details>
</details>

### Without Ground Truth:
When we remove the ground truth and ask the judge to compare the two outputs directly, some of the overall statistics look like this:

**Agreement between the two agents:**

Of the 138 questions where both the agents got it wrong accuracy-wise, the judge found that:
- 54 questions had `FULL_AGREEMENT` - the two agents returned the exact same answer
- 26 questions had `PARTIAL_AGREEMENT` - the two agents returned answers that had some overlap but were not identical
- 58 questions had `TOTAL_DISAGREEMENT` - the two agents returned completely different answers

For instances where both the agents got wrong answers, these could point to cases where that the benchmark ground truth may be ambiguous or incorrect, or that there are multiple valid interpretations of the question. While ambiguity cannot be ruled out in any of these three categories, FULL_AGREEMENT is the strongest indicator since both agents independently arrived at the same answer despite using different data models and query languages.

<details open>
<summary>Example</summary>

>Question: "In posts with 1 comment, how many of the comments have 0 score?"
```sql
-- Gold SQL: 
SELECT COUNT(T1.id) FROM comments AS T1 INNER JOIN posts AS T2 
ON T1.PostId = T2.Id WHERE T2.CommentCount = 1 AND T2.Score = 0
-- filters posts with 1 comment that also have a post score of 0

-- Predicted SQL:
SELECT COUNT(c.Id) FROM comments AS c INNER JOIN posts AS p 
ON c.PostId = p.Id WHERE p.CommentCount = 1 AND c.Score = 0
-- filters comments with score 0, on posts that have 1 comment

-- Predicted SPARQL:
SELECT ( COUNT( ?comment ) AS ?count ) WHERE {
    ?post <http://codecomt.org/schema#commentCount> 1 .
    ?comment a <http://codecomt.org/schema#Comment> ; 
    <http://codecomt.org/schema#onPost> ?post ; 
    <http://codecomt.org/schema#commentScore> 0 .
    }
```
Here, on manual inspection, both the SQL and SPARQL outputs seem to answer the question as intended, yet the BIRD benchmark has a different gold SQL that seems to be infact wrong. But the judge marks both the SQL and SPARQL outputs as wrong because they don't match the gold SQL output.
</details>

<details open>
<summary>Example</summary>

>Question: "State all the tags used by Mark Meckes in his posts that don't have comments."
```
Gold SQL output:       Predicted SQL and SPARQL output:
-----------------      -------------------------------
  <books>                books
  <books>
  <books>
  <books>
  NULL                   
```
The judge marks both the predicted outputs as incorrect and reasons that it returns only the 'books' tag but omits the NULL (untagged) post value present in the SQL result, because it only matches explicit Tag entities and ignores posts with no tags.

This is a case where the definition of a correct answer is ambiguous. The question asks to "state all the tags" but does not specify whether untagged posts should be included as NULL or ignored. Both outputs are defensible interpretations of the question, and the judge's preference between them could be subjective.
</details>

So, out of the 138 questions that both agents got wrong, they fully agreed on the same wrong answer for 54 such cases which could suggest that these are either coincidentally the same wrong answer or that the benchmark's gold answer is ambiguous or incorrect.

### User Preference
Apart from the consensus status, the judge also picks a winner between the two agents based on which answer a real user would prefer using criteria like plausibility, utility, and confidence. The results are:
- GRASP output is preferred in 64% of cases
- CHESS output is preferred in 31.4% of cases
- Both outputs are equally preferred in 4.6% of cases

The judge reasons that GRASP outputs are richer - with supporting context like underlying counts alongside ratios, dates alongside computed ages and clearer labels make the output appear more verifiable and internally consistent. This preference score is a useful signal but should not be interpreted as a quality signal independent of accuracy.

### Cost Comparison

Both CHESS and GRASP used GPT-5-mini for query generation and judge evaluation.

CHESS was run in the IR_SS_CG configuration (Schema Selector enabled, Unit Tester disabled), which is the leaner of its two configurations - the IR_CG_UT variant with the Unit Tester costs roughly 90–100$ for 500 questions. With Schema Selector, CHESS costs approximately $40–50 for 500 questions.

GRASP costs approximately $4–5 for 500 questions.

| | Cost for 500 questions |
|---|---|
| CHESS (IR_SS_CG) | ~$40 |
| GRASP | ~$5 |

## Ablation
### Evidence vs No Evidence
The BIRD benchmark provides an evidence field for each question. The question is whether it helps either of the agents disproportionately or if it is equally helpful for both. To test this, GRASP was re-run on all 500 questions without the evidence field.

| | Soft F1 | Relaxed F1 |
|---|---|---|
| SPARQL with evidence | 22.38% | 46.64% |
| SPARQL without evidence | 15.13% | 36.45% |

Removing evidence drops GRASP's relaxed F1 by 10.2 points. To see whether the drop is symmetric, the no-evidence run was evaluated on the two divergent subsets.
On the 84 questions that only CHESS answered correctly, removing evidence got:
| | SPARQL correct | SPARQL incorrect |
|---|---|---|
| SQL correct | 15 | 42 |
| SQL incorrect | 2 | 25 |

On the 30 questions where only GRASP answered correctly,
| | SPARQL correct | SPARQL incorrect |
|---|---|---|
| SQL correct | 6 | 5 |
| SQL incorrect | 8 | 11 |

Both systems lost accuracy without evidence, and both gained some wins on the other's previously exclusive subset. There is no clear signal that the evidence favoured one agent over the other disproportionately.

### Generic vs Semantic RDF
As specified in the implementation section, the generic RDF mapping is made by an automatic conversion using the same column names and table names and doing a basic mapping while semantic mapping does some key adjustments. The question is whether these adjustments make a difference in the accuracy of the GRASP agent compared to what a generic mapping would produce, especially for decreasing the non-logical errors which were typically caused by structural mismatch.

For example, `student_club` performed quite well with GRASP but had a higher non-logical error rate of 8% as compared to other databases that had also performed well. With the generic mapping, the difference in accuracy is not significant.
- Semantic RDF mapping: 71% accuracy
- Generic RDF mapping: 75% accuracy

`debit_card_specializing` was the fourth worst performing database with GRASP. When testing the same with the generic mapping, the results don't change at all.
- Semantic RDF mapping: 43% accuracy
- Generic RDF mapping: 43% accuracy

But the databases that performed the worst with GRASP were `california_schools`, `card_games` and `financial` which also had the highest non-logical error rates among all databases and highest performance gaps. We tested these with the generic mapping as well to see how the accuracy changes:

- For `card_games`:
    - Semantic RDF mapping: 28.8% accuracy
    - Generic RDF mapping: 17.3% accuracy

- For `california_schools`:
    - Semantic RDF mapping: 33.33% accuracy
    - Generic RDF mapping: 16.67% accuracy

- For `financial`:
    - Semantic RDF mapping: 37.5% accuracy
    - Generic RDF mapping: 25% accuracy

So for the databases with the highest error rates, the semantic mapping outperforms the basic mapping. These databases tend to have high column counts with ambiguous or opaque naming like `financial` for instance has 15 columns named `A2` through `A16` in a single table, which could explain why the richer semantic mapping fares better. So semantic mapping helps when the barrier is in understanding the schema and matching the right predicates but, we can't say conclusively whether it helps as much when the barrier is in the logic of the query itself like wrong filtering or aggregations.

### Accuracy Judge: with gold query vs without
We also ran the accuracy judge without providing the gold and predicted queries i.e. evaluating on outputs alone to see how much the judge's correctness evaluation relies on checking the logic of the query vs just checking the output values. 
The results when we remove the gold and predicted queries are:
||||
|---|---|---|
| | SPARQL CORRECT | SPARQL INCORRECT |
| SQL CORRECT | 48.4% | 17.2% |
| SQL INCORRECT | 6.2% | 28.2% |

The accuracy evaluation is largely consistent between the two setups with a slight drop in accuracy for both agents when the judge doesn't have access to the queries. This suggests that the judge is primarily evaluating correctness based on the output values rather than the logic of the query, which is expected given that the judge is not a database expert and might not be able to fully parse and understand complex SQL or SPARQL queries. The judge's reasoning statements also focus more on the output values and their alignment with the question rather than detailed analysis of query structure.

## Conclusion
- As per the current setup, CHESS(66.4%) outperforms GRASP(55.6%) on the BIRD-SQL benchmark data.
- The standard BIRD Soft F1 metric penalises GRASP's outputs so a relaxed F1 metric and LLM judge evaluation give a more realistic picture of the performance gap.
- Both CHESS and GRASP agree on the same answer for 39%(54 out of 138) of the questions that both got wrong which could point to cases where the definition of a correct answer is ambiguous.
- GRASP's outputs are marked as richer by the judge LLM in terms of readability and utility.


## Literature References
- [BIRD](https://arxiv.org/pdf/2305.03111)
- [CHESS](https://arxiv.org/pdf/2405.16755)
- [GRASP](https://ad-publications.cs.uni-freiburg.de/ISWC_grasp_WB_2025.pdf)

[^1]: [CHESS Architecture](https://arxiv.org/pdf/2405.16755)
