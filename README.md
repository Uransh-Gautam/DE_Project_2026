# DE_Project_2026

The database behind WorkGrid, our workspace portal for tracking team workload.

## About the Project

This is the Data Engineering part of WorkGrid. The Advanced Programming project covers the application itself, while this one is about the database underneath it: how the data is organised, how the tables connect, and how we use SQL to get useful answers out of it.

## What the Database Stores

The database keeps track of four things: departments, employees, projects, and allocations.

Every employee belongs to one department. An employee can work on many projects, and a project can have many employees, so a separate allocation record connects the two and stores how many hours were given. With this, questions like who is carrying the most hours or which project has the most people can be answered directly from the data.

## Design Approach

We kept the design small on purpose. Each piece of information is stored in only one place and tables are linked using keys, which avoids repeated data and keeps updates simple. The tables are normalised up to third normal form.

## What We Are Practising

- Creating tables with keys and constraints
- Inserting, updating, and deleting data
- Joining data across tables
- Grouping and adding up hours with aggregate functions
- Using CASE to label workload status
- Normalisation

## Tech Stack

- PostgreSQL

## Team

| Name | Enrolment Number |
|---|---|
| Uransh | 2501010690 |
| Puneet | 2501010361 |
| Varun Adwani | 2501010499 |
| Shlok Srivastava | 2501010434 |
