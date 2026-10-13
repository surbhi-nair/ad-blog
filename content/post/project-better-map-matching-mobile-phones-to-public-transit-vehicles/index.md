---
title: "Project Redesigning Map Matching Mobile Phones to Public Transit Vehicles"
date: 2026-04-27
author: "Gerrit Freiwald"
authorAvatar: "img/PTVM_mixed_emission_score.png"
tags: ["map-matching", "GTFS", "public transit", "mobile phones", "flutter", "C++", "Cpp"]
categories: ["project"]
image: "img/freiburg-nahverkehr.jpg"
draft: false
justified: true
---

In this blog post, we compare two dynamic map matching algorithms for matching a mobile phone to a public transit vehicle (PTV).

# Content

- [Content](#content)
- [Introduction](#introduction)
- [Background](#background)
  - [Introduction to GTFS](#introduction-to-gtfs)
  - [Trip Segments](#trip-segments)
  - [Close Trips](#close-trips)
  - [Active Trips](#active-trips)
  - [Map Matching to a Dynamic Map](#map-matching-to-a-dynamic-map)
    - [Events](#events)
    - [Hidden Markov Models](#hidden-markov-models)
- [PTS vs PTVM: Differences in the queries](#pts-vs-ptvm-differences-in-the-queries)
  - [Public Transit Snapper (PTS)](#public-transit-snapper-pts)
  - [Public Transit Vehicle Matcher (PTVM)](#public-transit-vehicle-matcher-ptvm)
    - [PTVM HMM](#ptvm-hmm)
      - [Emission Score](#emission-score)
      - [Transition Score](#transition-score)
- [Preprocessing and Implementation Details of PTVM](#preprocessing-and-implementation-details-of-ptvm)
  - [GTFS Reader](#gtfs-reader)
  - [Geocalendar Index](#geocalendar-index)
    - [HMM](#hmm)
    - [API](#api)
  - [User Device Emulation and Datasets](#user-device-emulation-and-datasets)
    - [Datasets](#datasets)
    - [User Device Emulation](#user-device-emulation)
- [Settings and Parameter Optimization](#settings-and-parameter-optimization)
  - [Available Parameters](#available-parameters)
  - [Parameter Optimization](#parameter-optimization)
    - [Method](#method)
      - [Automated Hyperparameter Optimization](#automated-hyperparameter-optimization)
      - [Activeness](#activeness)
    - [Critisizm](#critisizm)
    - [Results](#results)
- [Evaluation](#evaluation)
  - [RAM Usage](#ram-usage)
  - [Boot Time](#boot-time)
  - [Accuracy and Query Time](#accuracy-and-query-time)
    - [Method](#method-1)
    - [Results](#results-1)
      - [Query Time](#query-time)
      - [Accuracy](#accuracy)
- [Frontend](#frontend)
- [Installation](#installation)
- [Future Work](#future-work)
- [Conclusion](#conclusion)

# Introduction

We present an algorithm to deduce the public transit vehicle (PTV) a mobile phone is travelling in real time. In a nutshell, this is based on analyzing the last few GPS points of the device and applying our spatio-temporal map matching algorithm, which uses static (non-realtime) PTV schedule information.

This project aims to improve on Robin Wu's and my previous work [1-3], by improving accuracy and speed. We therefore re-design our previous spatio-temporal map-matching algorithm conceptually. We further improve query time by implementing the reworked backend in C++.

# Background

## Introduction to GTFS

The General Transit Feed Specification ([GTFS](https://developers.google.com/transit/gtfs)) lets PTV agencies describe the following static schedule properties:

**Trips**\
Each journey of a PTV from a start stop to a destination stop is called a trip.

**Shapes**\
Every trip of a public transit vehicle follows a specific shape, which can be described as a list of GPS points. For busses for example, the shape likely follows the most direct path in the street network from one stop to the next one, for all stops on the trip.

**Stop times**\
GTFS also gives us arrival and departure times for every stop on a trip.

**Service information**\
Every trip operates based on a service, which describes whether the trip is active on a given weekday. There can also be exceptions for specific dates, e.g. holidays.

## Trip Segments

We can subdivide a trip into k segments, where each segment describes the part of the trip between two stops.

## Close Trips

A trip or a trip segment is considered as close (to a point \\(p\\)) if any of the edges of the trip's/trip segment's shape pass through a radius of \\(p\\).

## Active Trips

We consider a trip as active during time point \\(t\\), if \\(\texttt{trip\_start} < t < \texttt{trip\_end}\\) for \\(\texttt{trip\_start}, \texttt{trip\_end} \in \texttt{stop_times}(\texttt{trip})\\).

Similarly, we consider an edge as active during time point \\(t\\), if the edge is part of a shape that is used by an active trip.

We can relax the definition of activeness by allowing for a slack \\((\texttt{earliness},\ \texttt{delay})\\) before and after the trip's start / end time.

## Map Matching to a Dynamic Map

Map Matching (MM) describes the process of fitting (often noisy) recorded points to the trajectory of a vehicle on a static map.
A typical use of MM is a navigation systen, where the gps points of a car get matched to a street network graph.

In Dynamic Map Matching (DMM), instead of matching to a static map, we match to moving targets on an underlying static graph. In our case, the GTFS shapes can be represented as a directed graph \\(G_\texttt{network}\\).
In this graph, each GPS point of a shape is represented as a node and successive points in a shape are connected with a directed edge.

### Events

Mobile devices emit Events \\(ev = (\texttt{lat}, \texttt{lon}, \texttt{time})\\), containing the geographical location and the current time.

### Hidden Markov Models

The map matching can be solved by using a [Hidden Markov Model (HMM)](https://en.wikipedia.org/wiki/Hidden_Markov_model).
A HMM is used when a process can likely be modeled by a Markov chain (The probability of transitioning from one state to another is solely dependant on the current state), but its states are unknown. We can reconstruct the states by finding the shortest path through the HMM, based on emission probabilities \\(P_\texttt{emission}\\) and transition probabilities \\(P_\texttt{transition}\\) (see [infographic]).

In both approaches PTS and PTVM, we get **HMM candidates** \\(c_j \in C_\texttt{PTS}\\) for each event \\(ev_i\\). With these, we create HMM graph \\(G_\texttt{HMM}\\), which consists of \\(|EV|\\) layers. We find the shortest path through the network

While the candidates in the old PTS approach are a filtered set of edges from GTFS shapes network graph \\(G_{network}\\), the new PTVM approach uses a set of filtered trips as candidates. In the following chapter, we explain the differences between PTS and PTVM in more detail.

# PTS vs PTVM: Differences in the queries

The aim of our dynamic map matching algorithms is to match a list of Events \\(EV = [ev_0, ..., ev_{n-1}]\\) to both spatial and temporal dimensions, such that the most likely trip \\(t_\texttt{best}\\) is returned.

<div id="fig-pts-ptvm-overview"></div>

In this chapter, we go through the query process of both PTS and PTVM, to highlight the differences in the queries. See [Figure 1](#fig-pts-ptvm-overview) for an overview.

{{< figure id="fig-pts-ptvm-overview" src="img/PTS_vs_PTVM_approaches.png" alt="PTS vs PTVM approaches" width="800" caption="> Figure 1 presents an overview over the pipeline differences on a trip matching query for PTS and PTVM. One can see that PTVM filters more trips early on in the query pipeline due to the rough time window filter. Furthermore, PTVM filters more trips before the HMM insertion and makes use of a mixed score, which incorporates the temporal component of the dynamic map matching directly into the HMM." >}}

## Public Transit Snapper (PTS)

On an incoming event from a user request, the older approach PTS starts by querying an R-Tree for close edges to the event location. PTS then filters roughly by time, so we just consider edges that are generally active during the event time. In this context, active means that the edge is used by a trip that is actively moving anywhere on its shape at the event time.

<div id="fig-g_network"></div>

Now, PTS adds these edges to a HMM. In PTS, HMM-candidates are edges. All edges that are close to the event locations [(see Figure 2)](#fig-g_network) are candidates in \\(G_\texttt{HMM}\\) (see [Figure 3](#fig-g_hmm)).

{{< figure id="fig-g_network" src="img/PTS_G_network.png" alt="G_network" width="800" caption="> Figure 2: \\(G_{\text{network}}\\) contains all edges. The two colored points are events (timestamped locations) emitted by a user device. In this example, all edges are close to an event, meaning they are within the event radius." >}}

<div id="fig-g_hmm"></div>

{{< figure id="fig-g_hmm" src="img/PTS_G_HMM.png" alt="G_HMM" width="800" caption="> Figure 3: \\(G_{\text{HMM}}\\) has one column for each event. Each event column contains all edges that are close to the event. The red path \\([\texttt{Start}, e^0_{ev_0}, e^0_{ev_1}, \texttt{End}]\\) is the shortest path through \\(G_{\text{HMM}}\\) (compare with the [\\(G_{\text{network}}\\)-Figure 2 above](#fig-g_network))." >}}

We then find the shortest path through \\(G_\texttt{HMM}\\), which gives a set of shortest path edges \\(E_\texttt{sp}\\). After this step, we take the GTFS shape that is most common along all \\(e \in E_\texttt{sp}\\). From this shape, we choose an active trip with the mose occurences on the edges of \\(E_\texttt{sp}\\). If there is a tie, only then do we do a more precise time based matching.
Generally, this old approach tries find a good spatial solution first, and only afterwards checks whether it is temporally valid.

## Public Transit Vehicle Matcher (PTVM)

In the new approach PTVM, both spatial and temporal dimensions are taken into consideration simultaneously. The weight of the dimensions can be tuned with a parameter \\(\psi\\). In the PTVM-approach, HMM-candidates are trips, not edges as in PTS.

<div id="fig-grid"></div>

PTVM starts by querying its Geocalendar Index (GCI) for crude spatial and temporal trip candidates. A GCI consists of a grid containing spatial candidate trips [(see Figure 4)](#fig-grid), as well as a calendar, which is a list of evenly spaced time intervals, which each contain trips that are active at any point during the interval.

{{< figure id="fig-grid" src="img/PTVM_Grid.png" alt="PTVM Grid" width="800" caption="> Figure 4: PTVM's spatial component of the GCI: Each cell in the grid contains a list of trips that are on any of the edges passing the cell. In this example, the blue shape is the shape trips \\(\texttt{T1}\\) and \\(\texttt{T2}\\), while the pink shape holds trips \\(\texttt{T3}\\) and \\(\texttt{T4}\\). The cell on the top left grid-position thus holds the list \\([\texttt{T3}, \texttt{T4}]\\), while the top right cell holds \\([\texttt{T1}, \texttt{T2}, \texttt{T3}, \texttt{T4}]\\)." >}}

<div id="fig-emission"></div>

After querying a list of trips \\(\texttt{GCI}(ev) = \texttt{grid}(ev) \cap \texttt{calendar}(ev)\\), we loop over all trip segments \\(ts_{t_i}\\) for all of these trips \\(t_i\\). We first filter by radius \\(r\\), then by a \\((\texttt{earliness},\ \texttt{delay})\\)-relaxed time window to get both close and active trip segments. On these remaining trip segments, we calculate a spatio-temporal score, [visualized in Figure 5](#fig-emission). For all edges \\(e_j = e_{ts_{t_i}}\\) in the event radius, we determine the closest point \\(p_{e_j}\\) to \\(ev\\). Based on the stop times of the trip segment, we interpolate the expected time \\(tp_{p_{e_j}}\\) of the PTV at each \\(p_{e_j}\\).

{{< figure id="fig-emission" src="img/PTVM_mixed_emission_score.png" alt="PTVM Mixed Emission Score" width="800" caption="> Figure 5: This Figure visualizes the calculation of the spatio-temporal emission score, that is calculated for each PTVM HMM candidate trip. The orange point shows a user device emitted event location \\(ev\\), the orange circle around it the event radius \\(r\\). The alternating black and red lines represent edges of an active trip segment passing through the event radius. The arrow points to the interpolated position of the trip on no delay or earliness \\(p_\texttt{on\_time}\\). For all edges \\(e_i\\) in the event radius, we determine the closest point \\(p_{e_i}\\) to \\(ev\\), represented as turqouise points. Based on the stop times of the trip segment, we interpolate the expected time of the PTV at each \\(p_{e_i}\\). The final emission score for this trip is the best combination of time discrepancy and spatial distance." >}}

<div id="eq-emission-equation"></div>

The spatio-temporal score is then calulcated [as followed in Equation 1](#eq-emission-equation), using the tunable parameter \\(\psi \in [0, 1]\\) and the time at the position where the PTV should be without any delay \\(tp_\texttt{on\_time}\\):

<div id="fig-temporal-emission"></div>

\begin{align}
\texttt{score}(ts_{t_i}) &= \psi \cdot \texttt{spatial}(ts_{t_i}) + (1 - \psi) \cdot \texttt{temporal}(ts_{t_i})\\\\[1em]
\texttt{spatial}(ts_{t_i}) &= \frac{\texttt{dist}(p_{e_j},\ ev)}{r}\\\\[1em]
\texttt{temporal}(ts_{t_i}) &= \begin{cases}
  \frac{tp_\texttt{on\_time} - tp_{p_{e_j}}}{\texttt{allowed\_delay}}, & \text{if trip delayed:}\ (tp_{p_{e_j}} < tp_\texttt{on\_time})\\\\
  \frac{tp_{p_{e_j}} - tp_\texttt{on\_time}}{\texttt{allowed\_earliness}}, & \text{if trip early:}\ (tp_\texttt{on\_time} < tp_{p_{e_j}})\\\\
\end{cases}
\end{align}

The spatial component linearly increases from \\(\texttt{dist}(p_{e_j}) \geq r \to 0\\) to \\(\texttt{dist}(p_{e_j}) = 0 \to (1 - \psi) \cdot \texttt{max\_emission\_weight}\\).
The temporal component of the score is visualized [in Figure 6](#fig-temporal-emission).

{{< figure id="fig-temporal-emission" src="img/PTVM_temporal_emission.png" alt="PTVM Temporal Emission Score" width="800" caption="> Figure 6: The temporal component of the emission score is \\(0\\) for punctual \\(tp_{p_{e_j}}\\) and linearly increases to its maximum on tunable earliness and delay threshold values." >}}

In order to determine the HMM candidates, we choose the maximum trip segment score \\(c_{t_i} \max \texttt{score}(ts_{t_i})\\) for all trips. If \\(c_{t_i} < \texttt{emission_threshold}\\), trip \\(t_i\\) is chosen as a HMM candidate for event \\(ev\\). We can recycle \\(c_{t_i}\\) for the HMM emission score.

### PTVM HMM

A HMM is a layered directed acyclic graph (LDAG), which enables us to use a heap-queue-free layer relaxation algorithm to find the shortest path from start to the end node in \\(\mathcal{O}(|E|+|V|)\\) time. Here, \\(E_l \in E\\) holds all _trip nodes_ per event layer \\(l\\). \\(V_{l \to l+1} \in V\\) holds all _transition edges_ between layers \\(l\\) and \\(l+1\\). Further, \\(E_{(l, i)} \in E_l\\) points to the \\(i\\)-th trip candidate in layer \\(l\\). Similarly, \\(V_{(l, i) \to (l+1, j)} \in V_{l \to l+1}\\) points to the transition edges connecting the \\(i\\)-th trip candidate in layer \\(l\\) to the \\(j\\)-th trip candidate in layer \\(l+1\\).

The number of transition edges \\(V_{l \to l+1}\\) increases quadratically for any trip node additions to \\(E_{l}\\) or \\(E_{l+1}\\). Hence, finding the shortest path through the HMM and consequentially minimizing the PTVM query time profits from keeping the amount of trip nodes per layer as low as possible. This is one key reason why PTVM query time is that much quicker, as we will see in [the evaluation chapter](#evaluation).

In our HMM calculations, we minimize \\(\texttt{score} \in [0, \infty)\\) instead of maximizing Markov probabilities \\(p \in [0, 1]\\). This is equivalent to a HMM, as \\(\texttt{score}\\) is derived from the negative log-likelihood of the Markov probabilities.

<!-- TODO discuss similarity to Viterbi? Is this Viterbi? -->

<div id="eq-transition"></div>

#### Emission Score

The emission score is already precomputed in the candidate selection step. It indicates the relevance of a trip for an event (recall [Equation 1](#eq-emission-equation)):

#### Transition Score

The transition score can be expressed [as followed in Equation 2](#eq-transition), for layer \\(l\\) and the trip the user device has been matched to the previous request \\(t_\texttt{prev}\\):

\begin{align}
\texttt{transition}(E, V, t_\texttt{prev}) &= \texttt{trip\_change\_hmm}(V) + \texttt{trip\_change\_prev}(E, t_\texttt{prev})\\\\[1em]
\texttt{trip\_change\_hmm}(V) &= \begin{cases}
  0, & \begin{aligned}&\text{if the trip does not change}\\\\ &\text{between layers:}\\\\ &V_{i \to j} = V_{(l, i) \to (l+1, j)}\end{aligned}\\\\[0.5em]
  \texttt{transition\_penalty}, & \begin{aligned}&\text{if the trip changes}\\\\ &\text{between layers:}\\\\ &V_{i \to j} \neq V_{(l, i) \to (l+1, j)}\end{aligned}\\\\[0.5em]
\end{cases}\\\\[1em]
\texttt{trip\_change\_prev}(E, t_\texttt{prev}) &= \begin{cases}
  0, & \begin{aligned}&\text{if the previous matching}\\\\ &\text{result and the last layer are}\\\\ &\text{identical:}\ t_\texttt{prev} = E_{(|EV|-1, i)}\end{aligned}\\\\[0.5em]
  \texttt{trip\_change\_penalty}, & \begin{aligned}&\text{if the previous matching}\\\\ &\text{result and the last layer}\\\\ &\text{differ:}\ t_\texttt{prev} \neq E_{(|EV|-1, i)}\end{aligned}\\\\[0.5em]
\end{cases}\\\\[1em]
\end{align}

# Preprocessing and Implementation Details of PTVM

In this chapter, we discuss the preprocessing of GTFS data and further implementation details of PTVM.

PTVM essentially consists of 4 parts:

1. A GTFS Reader that reads the GTFS and writes it into datastructures
2. A Geocalendar Index that is able to query spatially and temporally local trips
3. A HMM that predicts the most likely trip candidate
4. An API to communicate with the frontend or a user device simulation

## GTFS Reader

The GTFS Reader reads GTFS files and writes it into datastructures.

Time-related data is converted to UTC, from the time zone marked in the GTFS agencies.txt file.

Geometric distances are generally measured with the haversine distance formula.

We break down the GTFS shapes into edges. As many shapes partially follow the same path as other edges, there are many duplicated edges. For the \\(243,657\\) shapes of the [full Germany dataset](https://gtfs.de/de/feeds/de_full/) for example, we can reduce the amount of edges from \\(109,668,551\\) to \\(12,526,535\\), which is a reduction of \\(88.58\\%\\).

The GTFS Reader calculates TripSegments ([see Table 1](#table-struct-members)), which is a spatial component of a trip.

Generally, we generate structs (e.g. Edge, Trip, TripSegment), accumulate all of them in an \\(\texttt{std::vector}\\) (e.g. Edges, Trips, TripSegments) and link to them with an index (e.g. EdgeId, TripId, TripSegmentId). For smaller GTFS data like the information from routes.txt, we just store a map mapping from the original route_id to what we need for the query.

<div id="table-struct-members"></div>

In the following [Table 1](#table-struct-members), we explain choices for some datastructures we had to make in order to optimize the RAM/Query-Speed tradeoff.

  | Name | Struct members or Type | Explanation |
  | --- | --- | --- |
  | Edge | float lat1, float lon1,<br>float lat2, float lon2,<br>float len_m | Edge lengths have to be calculated<br>multiple times during query time. |
  | Edges | std::vector\<Edge\> | Lists all edges. |
  | EdgeId | uint32_t | Links to Edges. There are 12,526,535<br>unique edges in GermanyGTFS,<br>2^32 = 4_294_967_296 suffices |
  | Trip | std::string route_id,<br>std::string service_id,<br>std::string shape_id,<br>std::vector\<TripSegmentId\> ts_ids | We use the original GTFS strings for easier debugging.<br>They do not take up a relevantamount of space.<br>Links to its edgesusing the trip segments. |
  | Trips | std::vector\<Trip\> | Lists all trips. |
  | TripId | uint32_t | Links to Trips. As a precaution,<br>covers more than 2^16 = 65,536 trips |
  | RelTripSegmentIdx | uint16_t | Specifies the position of a TripSegment within a Trip |
  | TripSegment | std::vector\<EdgeId\>,<br>RelTsIdx idx,<br>float len_m | References the edges of the TS,<br>the position where it is in the trip,<br>and the accumulated edge length |
  | TripSegmentId | uint32_t | There are usually more trip segments than trips,<br>2^32 = 4_294_967_296 suffices even for<br>the GermanyGTFS dataset |
  | Route | std::string agency_id,<br>std::string route_short_name,<br>uint8_t route_type,<br>uint32_t route_color,<br>uint32_t route_text_color | Contains the information from routes.txt |
  | RoutesMap | std::map\<std::string, Route\> | For easier debugging and implementation speed,<br>we resort to a std::map and choose not to have a<br>separate RouteId. This can be optimized in the future. |

## Geocalendar Index

A Geocalendar Index (GCI) can be queried for a trip candidate that is both spatially and temporally close to a given Event. Its purpose is reduce the amout of HMM trip candidates to check from the potentially large GTFS dataset.

For the spatial part of the GCI, we implement a grid with a fixed width and height for each cell (e.g. 5 kilometers). Each cell contains a \\(\texttt{std::vector}\\) of \\(\texttt{std::set\<TripId\>}\\) for every trip passing the cell geographically. The vector is sorted by \\(\texttt{TripId}\\).

We choose a grid for the sake of implementation speed, even though a tree-like structure (e.g. an R-Tree, see PTS) would likely speed up the PTVM query process a lot, as it would reduce the amount of trips to check at the very beginning of the query pipeline [(recall Figure 1)](#fig-pts-ptvm-overview). However, as we will see in the [evaluation section](#evaluation), the proof of concept stands and PTVM drastically outperforms PTS in query time already.

As for the temporal part of the GCI, we chose a \\(\texttt{std::vector}\\) of time slots \\(\texttt{std::set\<TripTime\>}\\) of equal size (e.g. 24 hours), where each time slot contains all trips that are at least partially active within the time slot. We store \\(\texttt{TripTime}\\)s instead of \\(\texttt{TripId}\\)s, in order to allow for trips that have a duration longer than the length of the time slots. For example, for a slot size of 24h and a daily operating TripId \\(1\\) with a trip duration of 30 hours, a time slot would hold \\(\\{(1, 2026.01.01), (1, 2026.01.02)\\}\\). \\(\texttt{std::set\<TripTime\>}\\) contents is sorted first by \\(\texttt{TripId}\\) and then by \\(\texttt{date}\\).

Hence, in order to query the GCI for \\(\texttt{TripTime}\\)s that are both in the right cell and in the right time slot, we apply a zipper algorithm. It zips the sorted geographic vector and time slot set in \\(\mathcal{O}(n + m)\\) during query runtime.

<div id="eq-gci"></div>

In a prior version of the GCI, we tried merging the spatial and temporal components in one vector [as in Equation 3](#eq-gci).

\begin{equation}
\underbrace{\texttt{std::vector}}\_{\text{grid idx}} \texttt{<}\underbrace{\texttt{std::vector}}\_{\text{calendar idx}} \texttt{<}\underbrace{\texttt{std::set\<TripTime\>}}_{\text{spat. \& temp. relevant}} \texttt{>}\texttt{>}
\end{equation}

However, this lead to a disproportionate increase in building time and RAM usage for a minor increase in query time.

### HMM

Our implementation of a HMM cholds up to \\(\texttt{MAX\_HMM\_STATES}\\) layers plus two single-node start/end layers. There is no preprocessing needed, as it is built newly for each query.

### API

The PTVM API serves the same endpoints as PTS, in order to communicate with the old frontend, except for \\(\texttt{/chat}\\), which could be implemented on demand. \\(\texttt{/map-match}\\) has been renamed to \\(\texttt{/trip-match}\\) and still returns the most likely trip. \\(\texttt{/connections}\\) still fetches the transfer options at the next stop and \\(\texttt{/shapes}\\) still responds with the shape corresponding to a given trip id.

## User Device Emulation and Datasets

As it would be very exhausting and expensive to develop on board of a bus or tram on a laptop to see if the dynamic map matching algorithm currently works, we simulate the movement of an event-emitting device by precalculating events along the shapes of a GTFS dataset.

### Datasets

<div id="table-datasets"></div>

For the following chapters on [parameter optimizaton](#settings-and-parameter-optimization) and [evaluation](#evaluation), we use the GTFS datasets in [Table 2](#table-datasets). They all have different sizes in terms of calendar range, shape length and number of trips.

| Dataset | Days | Routes | Trips | Trip<br>segments | Edges<br>(dedupl.) | Raw edges | Dedupl.<br>reduction | Avg trips<br>per edge |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Freiburg-Short | 6 | 45 | 33,573 | 1,245 | 19,184 | 180,567 | 89.4% | 395.5 |
| DE-Fern | 34 | 99 | 5,244 | 3,297 | 250,092 | 7,212,615 | 96.5% | 64.0 |
| DE-Regio | 34 | 1,129 | 113,579 | 36,271 | 806,549 | 9,016,350 | 91.1% | 67.3 |
| DE-Nah | 35 | 23,850 | 1,560,724 | 850,164 | 11,688,499 | 93,436,586 | 87.5% | 43.7 |
| DE-full | 35 | 25,078 | 1,679,547 | 888,877 | 12,526,535 | 109,668,551 | 88.6% | 46.4 |
| CH-CH | 367 | 5,125 | 1,889,884 | 126,642 | 1,591,966 | 64,243,970 | 97.5% | 273.0 |
| CH-EU | 367 | 5,125 | 1,889,884 | 130,949 | 2,984,707 | 77,895,162 | 96.2% | 175.1 |
| CH-CH-Short | 6 | 5,125 | 1,889,884 | 126,642 | 1,591,966 | 64,243,970 | 97.5% | 273.0 |
| CH-EU-Short | 6 | 5,125 | 1,889,884 | 130,949 | 2,984,707 | 77,895,162 | 96.2% | 175.1 |

We can observe that GTFS shapes share a lot of edges, in CH-CH even 97.5%. For this report, we mainly use Freiburg-Short for query-related questions. This is because it is smallest, which makes it easy for testing, but also because it has a high average trips per edge ratio, which makes testing for harder queries easier.

### User Device Emulation

In order to simulate the movement of an event-emitting device, we precalculate trajectories along each trip \\(t\\) as a list of events \\(ev_{(t, \delta_g, \delta_t)}\\). We simulate events every \\(k=5\\) seconds, and their lat/lon position is linearly interpolated along \\(t\\)'s shape.

Here, \\(\delta_g \in \mathcal{N(0, \sigma^2)}\\) describes Gaussian noise on top of the geographical position. We also add noise on top of the time component \\(\delta_t \in \texttt{AR1}(\texttt{min_delay},\ \texttt{max_delay})\\). \\(\texttt{AR1}\\) is an [autoregressive modeling function](https://en.wikipedia.org/wiki/Autoregressive_model), which ensures that the randomized earliness/delay stays within \\((\texttt{min_delay},\ \texttt{max_delay})\\) boundaries, but tends to move back to a \\((0, 0)\\)-delay, while accounting for plausible jumps in earliness/delay times between two stops. This way, as an example, we do not draft three minutes earliness for stop 1 and three minutes delay for stop 2 (which would make trips move unreasonably fast or slow, especially on shorter trip segments).

For each event on a trip segment (between two stops), we linearly interpolate the timepoint \\(tp\\) based on the simulated position and the arrival/departure time at a trip's previous and next stop.

<div id="fig-example-noisy-trajectory"></div>

See [Figure 7](#fig-example-noisy-trajectory) for an example for the spatial part of the event generation.

{{< figure id="fig-example-noisy-trajectory" src="img/noisified_shape.png" alt="Example noisy trajectory" width="800" caption="> Figure 7 shows a possible GPS trajectory of a person travelling along a PTV's shape. The red line represents a GTFS shape. The blue line shows noisy location data emmitted by a user's device. Each corner on the blue line symbolizes a user moving within 5 seconds. The green points show where the event generator passes a stop and thus moves on to the next trip segment." >}}

# Settings and Parameter Optimization

PTS and PTVM both have configurable parameters. We first show what parameters exist. Then, we explain how we optimize them for PTVM.  

## Available Parameters

<div id="table-hpo-params-1"></div>

For both PTS and PTVM, we can choose the allowed earliness/delay in minutes, as well the GPS radius in meters and the maximum amout of HMM states. For both, we choose the following configuration (see [Table 3](#table-hpo-params-1)). Post-optimization values are just for PTVM, as we do not optimize PTS parameters.

| Parameter | Value Pre-<br>Optimization | Value Post-<br>Optimization | Description |
| --- | --- | --- | --- |
| \\(\texttt{EARLINESS\_MINUTES}\\) | 5 | 5 | Maximum allowed earliness in minutes<br>for temporal candidate query component |
| \\(\texttt{DELAY\_MINUTES}\\) | 5 | 5 | Maximum allowed delay in minutes<br>for temporal candidate query component |
| \\(\texttt{MAX\_HMM\_STATES}\\) | 10 | 10 | Maximum number of HMM states to consider per event |
| \\(\texttt{GPS\_RADIUS\_M}\\) | 50 | <span style="background-color: #00ff3c;">74</span> | Radius in meters for spatial query component |

For the later evaluation, we leave \\(\texttt{GPS\_RADIUS\_M}\\) at 50 for PTS, but only increase it for PTVM.

<div id="table-hpo-params-2"></div>

For PTVM, we choose the following configurable parameters in [Table 4](#table-hpo-params-2):

| Parameter | Value Pre-<br>Optimization | Value Post-<br>Optimization | Description |
| --- | --- | --- | --- |
| \\(\texttt{NO\_TRIP\_PENALTY}\\) | 1000 | <span style="background-color: #00ff3c;">1695.79</span> | Penalty if no trip is assigned<br>(no matching found) |
| \\(\texttt{TRIP\_CHANGE\_PENALTY}\\) | 1000 | <span style="background-color: #00ff3c;">370.99</span> | Penalty for matching to a different trip than<br>the matching from last request |
| \\(\texttt{TRANSITION\_PENALTY}\\) | 100 | <span style="background-color: #00ff3c;">194.93</span> | Penalty if trips are different between events<br>of two HMM layers |
| \\(\texttt{EMISSION\_PENALTY}\\) | 1000 | <span style="background-color: #00ff3c;">22.72</span> | Maximum emission score.<br>All candidates above this threshold<br>are not included in the HMM |
| \\(\texttt{TEMPORAL\_WEIGHT}\\) | 0.5 | <span style="background-color: #00ff3c;">0.38</span> | Weighting factor for temporal and spatial<br>component of emission score.<br>0.5 means equal weighting.<br>0.3 means 30% temporal, 70% spatial. |
| \\(\texttt{CELL\_SIZE\_KM}\\) | 5 | 5 | Grid cell size in kilometers |
| \\(\texttt{CALENDAR_TIME_INTERVAL_H}\\) | 24 | 24 | Slot size of each calendar time interval in hours |

PTS has no other configurable parameters.

## Parameter Optimization

We optimize all parameters from the tables above, except for the following: \\(\texttt{CELL\_SIZE\_KM}\\) and \\(\texttt{CALENDAR_TIME_INTERVAL_H}\\) depend more on the GTFS dataset size. For bigger datasets, hardware constraints lead to bigger cells and calendar intervals. \\(\texttt{MAX\_HMM\_STATES}\\), \\(\texttt{EARLINESS\_MINUTES}\\) and \\(\texttt{DELAY\_MINUTES}\\) stay the same, in order to stay comparable with PTS.

### Method

In this chapter, we describe how we automate the parameter optimization. Furthermore, we introduce a metric on how to quantify the difficulty of a PTS/PTVM query.

#### Automated Hyperparameter Optimization

We can treat the PTVM parameter optimization as a hyperparameter optimization (HPO) problem, where we want to maximize the accuracy for multiple delays \\((0, 0)\\) and \\((3, 3)\\) minutes.

<div id="eq-hpo-score"></div>

We use [optuna](https://optuna.org/) with a [TPE optimizer](https://optuna.readthedocs.io/en/stable/reference/samplers/generated/optuna.samplers.TPESampler.html) to automate the HPO task. We start \\(N = (|\texttt{num\_cores}| - 2)\\) containerized PTVM instances with a different hyperparameter configuration \\(c\\). We then simulate trajectories [as described previously](#user-device-emulation) on \\(p\\%\\) of Freiburg-Short for \\((0, 0)\\) and \\((3, 3)\\) minute delays. As we want to optimize for both delays, we give each configuration a \\(\texttt{config\_score}\\) [(see Equation 4)](#eq-hpo-score). We prioritize \\(\texttt{acc}(c, (3, 3))\\) by weighting its accuracy higher: \\(w = 30\\%\\). We pick the best hyperparameter configuration \\(c_\texttt{best}\\) after two hpo phases.

\\[\texttt{config\_score}(c) = w \cdot \texttt{acc}(c, (0, 0)) + (1 - w) \cdot \texttt{acc}(c, (3, 3))\\]

In phase 1, the TPE explores the hpo config space in \\(T = 40\\) trials. Each trial starts \\(N\\) containerized PTVM instances with different hyperparameter configurations \\(c_{t, i}\\), for \\(0 \leq t < T\\) describing the trial and \\(0 \leq i < N\\) describing the PTVM instance. We simulate trajectories on \\(5\\%\\) of Freiburg-Short for feasible runtimes.

In phase 2, we pick the \\(N\\) best configurations and run them on \\(33\\%\\) of Freiburg-Short, in order to find a good robust configuration.

#### Activeness

<div id="fig-activeness-freiburg-short"></div>

In order to differentiate the difficulty of a query, we introduce _Activeness_. Trips and trip segments have Activeness \\(a_t\\) or \\(a_{ts}\\). We calculate Activeness based on how many trips pass an edge \\(e_t\\) within our time window: Activeness \\(a_{e_t}\\) of edge \\(e_t\\). Then, for each trip segment \\(ts_t\\) of trip \\(t\\), \\(a_{ts_t} = \texttt{avg}(a_{e_t})\\) for all edges within the trip segment. Similarly, we calculate a trip's Activeness \\(a_t = \texttt{avg}(a_{e_t})\\) for all edges of the trip. Generally, we expect a query to be more difficult for a more active trip or trip segment, as there are more candidates to choose from. See [Figure 8](#fig-activeness-freiburg-short) for an example of the activeness of Freiburg-Short (for Wednesday, 15th of October 2025).

{{< figure id="fig-activeness-freiburg-short" src="img/activeness_freiburg-short.png" alt="Activeness Freiburg Short" width="800" caption="> Figure 8 shows the activeness of Freiburg-Short dataset on Wednesday, 15th of October 2025. We can see that the mean edge activeness for whole trips is around 100, meaning that a user device emitting events on a random trip \\(t\\) can be expected to have 100 trips passing this edge on said Wednesday to choose from, for each edge that is within the event radius. For tripsegments, we can see that some surpass a per-tripsegment-average of 400 trips per edge. These tripsegments contain highly travelled edges. For Freiburg-Short, this would be the tram tracks above the main station, and the main station bus hub for example.">}}

### Critisizm

We ran the HPO on an older version of [user device emulation](#user-device-emulation), where unreasonably large earliness/delay jumps were possible between two stops. This lead to much worse predictions, as some (especially smaller) trip segments had very few events generated, making it hard to match to. For this reason, we might not have found a parameter composition that is close to optimal yet. However, we can still see an improvement, as we will see in the next section.

As the event generator does not simulate mock-trips, where the target is no trip, the HPO can choose to assign an arbitrarily high value to \\(\texttt{NO\_TRIP\_PENALTY}\\). In real life scenarios, it can often be more likely not to be matched to a trip. In that case, \\(\texttt{NO\_TRIP\_PENALTY}\\) should be much lower, possibly even negative.

### Results

<div id="fig-0-0-opt-ts-acc-qtime"></div>

As for the results of the parameter optimization, we can see that giving PTVM a higher \\(\texttt{GPS\_RADIUS\_M}\\) leads to a better matching for trips with a small delay. This causes an improved calculation of the emission score (recall [Figure 5](#fig-emission)). As a consequence, the average accuracy on even very active trips remains high for small delays (see Figures [9](#fig-0-0-opt-ts-acc-qtime) and [10](#fig-0-0-opt-ts-quantiles)).

\\(\texttt{TRIP\_CHANGE\_PENALTY}\\)'s value is nearly a third of what it was before the optimization. This could be interpreted as the optimizer believing that it is more likely to change trip mid simulation. However, if we look at how drastically lower the maximum \\(\texttt{EMISSION\_PENALTY}\\) is, the \\(\texttt{TRIP\_CHANGE\_PENALTY}\\) is still quite high. As an example, for \\(\texttt{MAX\_HMM\_STATES} = 10\\), the maximum accumulated \\(\texttt{EMISSION\_PENALTY}\\) is \\(10 \cdot 22.72 = 227.2\\). We now assume the user got matched to the same trip \\(t_1\\) for the last 9 events (accumulated \\(\texttt{TRAMSITION\_PENALTY} = 0\\)). But now there is an option to change to a different trip \\(t_2\\) on the last layer of the HMM. The shortest path through the HMM would always choose \\(t_1\\), even with maximal \\(\texttt{EMISSION\_PENALTY} = 22.72\\), over \\(t_2\\) with an added \\(\texttt{TRIP\_CHANGE\_PENALTY}\\). So, realistically, \\(\texttt{TRIP\_CHANGE\_PENALTY}\\) is only relevant if the previously matched trip \\(t_1\\) was not a HMM candidate on the last layer, which would make the parameter \\(\texttt{TRIP\_CHANGE\_PENALTY}\\) useless, as every trip would get that penalty.

We can reason similarly for \\(\texttt{TRANSITION\_PENALTY}\\). As \\(194.93\\) is nearly as high as \\(10 \cdot \texttt{EMISSION\_PENALTY} = 227.2\\), changing trip mid-way through the HMM is only an option if the currently most likely trip was not a HMM candidate for previous events. But if that is the case, why would PTVM need to drag along up to 10 HMM candidates, if it only allows for the same trip to be on the shortest HMM path? We tried using less than 10 HMM candidates briefly, but in order to stay comparable with PTS, we chose not to lower \\(\texttt{MAX\_HMM\_STATES}\\), allthough this could be worth looking into in more detail.

After the HPO, the value for \\(\texttt{TRANSITION\_PENALTY}\\) nearly doubled, while \\(\texttt{EMISSION\_PENALTY}\\) is 44 times smaller. Given that the ratio of parameters changed this drastically, it is astonishing that the unoptimized PTVM version performs this well.

{{< figure id="fig-0-0-opt-ts-acc-qtime" src="img/parameter_optimization/0-0/comparison_trip_segments.png" alt="Default vs Optimized Parameter PTVM Performances" width="800">}}
{{< figure id="fig-3-3-opt-ts-acc-qtime" src="img/parameter_optimization/3-3/comparison_trip_segments.png" alt="PTS vs PTVM approaches" width="800" caption="> Figure 9 compares two versions of PTVM. The blue version has unoptimized default parameters, the orange version optimized parameters (see Tables [3](#table-hpo-params-1) and [4](#table-hpo-params-2)). While PTVM version with optimized parameters is minimalistically slower, the performance gain in accuracy is substantial. It has to be noted that the parameter optimization was performed on an earlier version of the event generator. For that reason, the accuracy measures might not perfectly match with the graphs in the later evaluation section." >}}

<div id="fig-0-0-opt-ts-quantiles"></div>

{{< figure id="fig-0-0-opt-ts-quantiles" src="img/parameter_optimization/0-0/quantiles_line_segments.png" alt="PTS vs PTVM approaches" width="800">}}
{{< figure id="fig-3-3-opt-ts-quantiles" src="img/parameter_optimization/3-3/quantiles_line_segments.png" alt="PTS vs PTVM approaches" width="800" caption="> Figure 10 describes how well the baseline performs vs the optimized PTVM version for two earliness/delay settings (0-0) and (3-3). For both, the optimized version shows improved accuracy while being only marginally slower. Both follow the same accuracy drop from quantile 50, but the accuracy of the optimized version increases again for the most difficult cases." >}}

# Evaluation

In this chapter, we compare PTS and PTVM with regard to RAM usage, boot time, query time and accuracy. We only use datasets described in [Table 2](#table-datasets).

## RAM Usage

<div id="table-ram-pts-ptvm"></div>

We compare the RAM usage of PTS and PTVM on different datasets in [Table 5](#table-ram-pts-ptvm). The RAM evaluation as conducted on a home machine with 54GB RAM. As we can see, PTVM uses up significantly less space.

Freiburg-Short is a [VAGFR](https://www.vag-freiburg.de/service-infos/downloads/gtfs-daten) dataset reduced to trips active on 2025/10/15.
All DE-* datasets are from [gtfs.de](https://gtfs.de/de/feeds/).
CH-CH is the full dataset of [Swiss Opentransport](https://data.opentransportdata.swiss/dataset/timetable-2026-gtfs2020), excluding shapes that are not within swiss borders.
CH-EU is the same dataset, including all shapes within European borders, thus including more edges than CH-CH.
CH-*-Short are the same datasets as CH-CH and CH-Europe, but reduced to trips active on 2025/10/15.

| GB | Freiburg<br>-Short | DE-Fern | DE-Regio | DE-Nah | DE-full | CH-CH | CH-EU | CH-CH<br>-Short | CH-EU<br>-Short |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Disk use GTFS | 53M | 313M | 481M | 5.8G | 6.6G | 4.9G | 5.5G | 4.8G | 5.4G |
| RAM usage PTS | 0.58 | 4.61 | 7.43 | 87.96 | 99.42 | 52.16 | 62.11 | 51.31 | 61.25 |
| RAM usage PTVM | 0.28 | 0.56 | 2.03 | 22.89 | 25.43 | 60.48 | 62.82 | 15.83 | 18.16 |

We can observe that PTVM generally uses a lot less RAM than PTS, only for CH-CH and CH-EU it is inverted. The reason is are the 364 days that Swiss Opentransport support for every trip in their GTFS dataset, which all land in the PTVM calendar. Interestingly, even though CH-EU(-Short) has double the amount of (deduplicated) edges to CH-CH(-Short), the used RAM is only 2.5GB more. See right plots of Figure [11](#fig-disk-size).

<div id="table-speed-pts-ptvm"></div>

## Boot Time

We compare the boot time of PTS and PTVM on different datasets in [Table 6](#table-speed-pts-ptvm). We define boot time as the time needed to read the GTFS files and create the data structures, from program launch until the API is live. We abbreviate _pre-generator_ with _PG_, as PTS pre-generates the datastructures needed by python with a C++ program. These datastructures are saved to disk as json files. PTS no PG just has to load these files, that have to be generated once for each new GTFS set. For now, PTVM does all the datastructure generation (e.g. trip segment generation) on each start.

| Boot Time | Freiburg<br>-Short | DE-Fern | DE-Regio | DE-Nah | DE-full | CH-CH | CH-EU | CH-CH<br>-Short | CH-EU<br>-Short |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| PTS with PG | 26.11s | 1.93m | 3.62m | 50.25m | 55.90m | 32.82m | 37.16m | 32.56m | 37.26m |
| PTS no PG | 6.72s | 23.09s | 1.07m | 16.00m | 26.36m | 10.34m | 11.29m | 9.25m | 10.86m |
| PTVM | 10.80s | 16.37s | 1.08m | 16.14m | 17.46m | 1.43h | 1.44h | 8.29m | 9.39m |

<div id="fig-disk-size"></div>

For the same reasons concerning the amount of days, as described in [the previous chapter](#ram-usage), the boot time for CH-CH and CH-EU is a lot slower. The amount of edges does not make a big impact in boot time, if we compare CH-CH(-Short) and CH-EU(-Short). See left plots of Figure [11](#fig-disk-size).

{{< figure id="fig-disk-size-overview" src="img/boot_ram_vs_disk_size_overview.png" alt="ram and boot time plot overview" width="800">}}
{{< figure id="fig-disk-size" src="img/boot_ram_vs_disk_size_zoom.png" alt="ram and boot time plot zoom" width="800" caption="> Figure 11 shows the boot time and RAM usage of PTS and PTVM on different datasets against the disk size of the GTFS dataset. The lower two plots are a zoomed-in view of the clustered larger datasets in the upper plots. For most datasets, PTS uses more RAM than PTVM and is slower to boot. However, for the CH-CH and CH-EU datasets, PTVM uses more RAM than PTS and is a lot slower to boot. This is because of the calendar generation, which takes a long time for the 364 days of CH-CH and CH-EU. PTS does not do any calendar generation at all. This is why we create *-Short datasets, which only contain trips active on a few days.">}}

## Accuracy and Query Time

In this chapter, we evaluate how well PTS and PTVM perform in terms of accuracy and query time.

### Method

We consider all trips of the GTFS dataset VAGFR of Freiburg's PTV agency VAG on Wednesday 15th of October 2025. We precalculate simulated trajectories along each trip \\(t\\) as described in the chapter on [user device emulation](#user-device-emulation).

Not only do we consider query time and accuracy on every single trip, we also examine the same metrics for all trip segments along the way.

VAGFR contains 3329 trips that start on Wednesday 2025.10.15 00:00:00 and serve two or more stops within 24 hours from then. We generate 912,434 events for all trips, or on average 274 events per trip. As one PTS query averages 0.482 seconds, we can expect a runtime of \\(\sim 122\\) hours on a single core to simulate all trips. As we want to speed up the simulation by parallelizing, we run several PTS backend instances with gunicorn. Only one backend instance does not suffice with one GIL-bound Flask API. With 8 processes, we get the simulation run time down to about 18 hours on a home machine with an AMD Ryzen 5 5600X.

We run this setup thrice for events with earliness/delay (0-0), (3-3) and (6-6). The higher the derivation from punctuality, the more trips we _expect to miss_. For example, if an edge has a very high activeness, with one trip every three minutes, a derivation window of three or even six minutes may lead to a matching to the trip before or after the target trip.

### Results

PTVM outperforms PTS in every aspect of query time and in most aspects of accuracy, as we will elucidate in the following sections.

#### Query Time

We observe that PTVM overwhelmingly outperforms PTS in terms of query speed. This is true for the median of the trips and trip segments (PTS around 6 times slower). The slowest 10% of all PTS queries are more than 10 times slower than the slowest 10% of PTVM, and the slowest 1% for PTS are around 20 times slower than for PTVM. See the right hand side of plots [12](#fig-0-0-eval-ts-quantiles) and [13](#fig-0-0-eval-trip-quantiles).

Also, the higher the difficulty of a query, (measured by the [activeness](#activeness) of the current trip segment), the longer both PTS and PTVM need to respond. However, the increase in query time for more difficult queries is much faster for PTS than for PTVM. While the query time for PTS is only X times slower than PTVM for the least active trip segment quantile, PTS is Y times slower than PTVM on the most active quantiles. See the right hand side of plot [14](#fig-0-0-eval-ts-activeness).

#### Accuracy

As we can see in Figures [12](#fig-0-0-eval-ts-quantiles) and [13](#fig-0-0-eval-trip-quantiles), PTVM outperforms PTS in accuracy for (0-0) and (3-3) earliness/delay. For (6-6), PTS has a slightly higher mean accuracy than PTVM, but also a higher failure rate.

As for the accuracy of PTS and PTVM on trip segments with different activeness levels, we can see that PTS slightly outperforms PTVM for low activeness and stays on par for medium activeness. However, for high activeness, PTVM outperforms PTS by a large margin. See the left hand side of plot [14](#fig-0-0-eval-ts-activeness).

<div id="fig-0-0-eval-ts-quantiles"></div>

{{< figure id="fig-0-0-eval-ts-quantiles" src="img/evaluation_ptvm_pts/0-0/comparison_trip_segments.png" alt="PTS vs PTVM TS" width="800">}}
{{< figure id="fig-3-3-eval-ts-quantiles" src="img/evaluation_ptvm_pts/3-3/comparison_trip_segments.png" alt="PTS vs PTVM TS" width="800">}}
{{< figure id="fig-6-6-eval-ts-quantiles" src="img/evaluation_ptvm_pts/6-6/comparison_trip_segments.png" alt="PTS vs PTVM TS" width="800" caption="> Figure 12 shows the differences in accuracy and query time for both PTS and PTVM on the full Freiburg-Short dataset. Generally, we can observe that PTS scores a higher accuracy than PTS for all sorts of delays, while serving dominantly faster query times. PTS query times are around six times slower than PTVM, but can be even significantly slower for especially hard requests. For earliness/delay (0-0), four fifths of Freiburg-Short's tripsegments are correctly classified by PTVM, while PTS barely surpasses fifty percent. Without any delay, PTVM fails to classify 1/6 trip segments for at least \\(70\\%\\) of requests on this trip segment. PTS fails between 1/5 and 1/4. For earliness/delay (3-3), both PTS and PTVM lose perfect rate and increase failure rate. PTS shows a little higher degradation than PTVM. As for earliness/delay (6-6), the mean accuracy of PTS is even a bit better than PTVM, while having a similar failure rate.">}}

<div id="fig-0-0-eval-trip-quantiles"></div>

{{< figure id="fig-0-0-eval-trip-quantiles" src="img/evaluation_ptvm_pts/0-0/comparison_whole_trips.png" alt="PTS vs PTVM TS" width="800">}}
{{< figure id="fig-3-3-eval-trip-quantiles" src="img/evaluation_ptvm_pts/3-3/comparison_whole_trips.png" alt="PTS vs PTVM TS" width="800">}}
{{< figure id="fig-6-6-eval-trip-quantiles" src="img/evaluation_ptvm_pts/6-6/comparison_whole_trips.png" alt="PTS vs PTVM TS" width="800" caption="> Figure 13 shows the same metrics as [Figure 12](#fig-0-0-eval-ts-quantiles), but this time for whole trips instead of trip segments. For delays (0-0) and (3-3), PTVM manages to perfectly classify over 50% of all trips of Freiburg-Short. PTS can be expected to fail at least a few queries per trip, even though its mean accuracy hovers around 3/4 to 4/5, being outperformed by PTVM every time. As for (6-6), the mean accuracy is higher for trips than for trip segments. This is due to Freiburg-Short being skewed with more trips with less activeness. This way, both PTS and PTVM score a higher mean accuracy, as most parts of trips are easier to match to than a few very active trip segments. As explained earlier, we can expect a high failure rate for such high delays on static datasets.">}}

<div id="fig-0-0-eval-ts-activeness"></div>

{{< figure id="fig-0-0-eval-ts-activeness" src="img/evaluation_ptvm_pts/0-0/quantiles_line_segments.png" alt="PTS vs PTVM TS" width="800">}}
{{< figure id="fig-3-3-eval-ts-activeness" src="img/evaluation_ptvm_pts/3-3/quantiles_line_segments.png" alt="PTS vs PTVM TS" width="800">}}
{{< figure id="fig-6-6-eval-ts-activeness" src="img/evaluation_ptvm_pts/6-6/quantiles_line_segments.png" alt="PTS vs PTVM TS" width="800" caption="> Figure 14 shows the average accuracy of PTS and PTVM depending on the difficulty of the query, measured by average trip segment activeness. We can observe that the accuracy of PTS drastically drops for more difficult queries, while PTVM's stays around 4/5 correct matches for (0-0) and 3/4 for (3-3). Only for (6-6) does the accuracy drop for trips from medium difficulty to hard, but even then stays around 50%. As for the query times, PTS needs considerably more time for a harder query than PTVM, even though we can also see a small increase in query time for PTVM.">}}

# Frontend

PTVM works with the same frontend as PTS and has not been changed relevantly for this project. See [Gerrit Freiwald's Bachelor Thesis](https://ad-publications.cs.uni-freiburg.de/theses/Bachelor_Gerrit_Freiwald_2022.pdf) for a more in-depth look.

# Installation

Checkout our [GitHub repository](https://github.com/TheRealTirreg/PublicTransitSnapper/) and follow the instructions in the README.md.

# Future Work

The dynamic public transit vehicle matching of PTVMatcher can be potentially improved in multiple ways.

In order to upgrade query speed, one could replace the GCI grid with an R-Tree structure.

Furthermore, one could store \\((\texttt{TripId}, \texttt{TripSegmentId})\\)-tuples in the GCI spatial component (Grid or R-Tree), which would raise RAM usage, but drastically reduce the amount of trip segments that need to be looped over for each query.

Another possible query speed gain is to cache HMM layers for each user, as emissions do not need to be recalculated for each request.

As mentioned in [Equation 3](#eq-gci), one could merge the spatial and temporal components of the GCI into one data structure. This would reduce the amount of trips to check for each query, but would increase RAM usage and boot time.

Instead of the linear emission functions in the spatio-temporal-score (recall [Figure 5](#fig-emission)), we could try using a Gaussian distribution, as Newson and Krumm did in [Hidden Markov Map Matching Through Noise and Sparseness](https://dl.acm.org/doi/10.1145/1653771.1653818). This might improve the candidate selection at least for the geographical part of the spatio-temporal score, as GPS error can be modelled as a Gaussian.

In order to reduce boot times when multiple boot times are needed for the same dataset, one could pre-compute the needed datastructures (e.g. TripSegments, GCI, ...) in a similar manner to PTS. One could save the pre-computed datastructures to hard drive and then load them on boot request.

At the moment, both approaches have the downside that they rely on linear interpolation for estimating where the PTV is between two stops. This is not accurate for trip segments with varying speeds. This could be learnt for each trip, or inferred from OSM data, in order to improve the emission score.

# Conclusion

We present PTVM, a dynamic map matching algorithm that outperforms PTS, an earlier version. PTVM outperforms PTS, in terms of RAM usage and query time by a large margin. PTVM also outperforms in boot time, even though we have not yet implemented pre-computation of datastructures. As for accuracy, PTVM outperforms PTS for delays and early arrivals of up to 3 minutes, while being on par for delays of 6 minutes on the dataset of Freiburg-Short. PTVM is especially good at matching trips and trip segments with a high activeness, where PTS fails to match correctly in most cases.

We also show how we optimize the parameters of PTVM, in order to achieve the best possible accuracy for a given dataset.
