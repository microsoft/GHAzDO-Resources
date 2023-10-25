'use strict';

const express = require('express');
const bodyParser = require('body-parser')
const version = require('./version');
const { Pool } = require('pg');

// Load environment
require('dotenv').config()

// Database pool
const pool = new Pool({
  user: process.env.DB_USERNAME,
  host: process.env.DB_HOST,
  database: process.env.DB_NAME,
  password: process.env.DB_PASSWORD,
  port: process.env.DB_PORT,
})

// Application
const app = express();
app.use(bodyParser.json())
app.use(bodyParser.urlencoded({
  extended: true
}));

const port = process.env.PORT || 8080;

// Route - default
app.get('/', (req, res) => {
  res.status(200).send(JSON.stringify({ name: version.getName(), version: version.getVersion() }));
});

// Route - user search
app.get("/users", function (req, res) {
  let search = "%";

  if (req?.params?.q) {
    search = req.params.q;
  }

  const squery = `SELECT * FROM users WHERE name LIKE '${search}';`
  pool.query(squery, (err, results) => {
    if (err) {
      console.log(err, results)
    }
    else {
      res.send(results.rows)
    }
  });
});

// Start the server
app.listen(port, () => {
  console.log(`Express app up and running on http://localhost:${port}`);
})
