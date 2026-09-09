migrate((db) => {
  const dao = new Dao(db);

  const wards = new Collection({
    id: "wards0000000000",
    name: "wards",
    type: "base",
    listRule: "",
    viewRule: "",
    createRule: "",
    updateRule: "",
    deleteRule: "",
    schema: [
      { name: "ward_number", type: "number", required: true },
      { name: "ward_name", type: "text", required: true },
      { name: "zone", type: "text" }
    ]
  });
  dao.saveCollection(wards);

  const workers = new Collection({
    id: "workers000000000",
    name: "workers",
    type: "base",
    listRule: "",
    viewRule: "",
    createRule: "",
    updateRule: "",
    deleteRule: "",
    schema: [
      { name: "name", type: "text", required: true },
      { name: "employee_id", type: "text", required: true },
      { name: "assigned_ward", type: "relation", required: true, options: { collectionId: wards.id, maxSelect: 1 } }
    ],
    indexes: ["CREATE UNIQUE INDEX idx_worker_emp_id ON workers (employee_id)"]
  });
  dao.saveCollection(workers);

  const scanners = new Collection({
    id: "scanners0000000",
    name: "scanners",
    type: "base",
    listRule: "",
    viewRule: "",
    createRule: "",
    updateRule: "",
    deleteRule: "",
    schema: [
      { name: "scanner_id", type: "text", required: true },
      { name: "secret_key", type: "text", required: true },
      { name: "assigned_ward", type: "relation", required: false, options: { collectionId: wards.id, maxSelect: 1 } },
      { name: "assigned_worker", type: "relation", required: false, options: { collectionId: workers.id, maxSelect: 1 } },
      { name: "status", type: "select", options: { values: ["active", "maintenance", "decommissioned"] } }
    ],
    indexes: ["CREATE UNIQUE INDEX idx_scanners_id ON scanners (scanner_id)"]
  });
  dao.saveCollection(scanners);

  const properties = new Collection({
    id: "properties00000",
    name: "properties",
    type: "base",
    listRule: "",
    viewRule: "",
    createRule: "",
    updateRule: "",
    deleteRule: "",
    schema: [
      { name: "tag_uid", type: "text", required: true },
      { name: "eb_sc_number", type: "text", required: true },
      { name: "address", type: "text" },
      { name: "ward", type: "relation", required: true, options: { collectionId: wards.id, maxSelect: 1 } },
      { name: "property_type", type: "select", options: { values: ["residential", "commercial", "institutional"] } }
    ],
    indexes: [
      "CREATE UNIQUE INDEX idx_properties_tag_uid ON properties (tag_uid)",
      "CREATE UNIQUE INDEX idx_properties_eb_sc ON properties (eb_sc_number)"
    ]
  });
  dao.saveCollection(properties);

  const audit_logs = new Collection({
    id: "auditlogs000000",
    name: "audit_logs",
    type: "base",
    listRule: "",
    viewRule: "",
    createRule: "",
    updateRule: "",
    deleteRule: "",
    schema: [
      { name: "scanner", type: "relation", required: true, options: { collectionId: scanners.id, maxSelect: 1 } },
      { name: "property", type: "relation", required: true, options: { collectionId: properties.id, maxSelect: 1 } },
      { name: "timestamp", type: "date", required: true },
      { name: "status", type: "bool" },
      { name: "hmac_verified", type: "bool" }
    ]
  });
  dao.saveCollection(audit_logs);

  const compliance_scores = new Collection({
    id: "compliancescore",
    name: "compliance_scores",
    type: "base",
    listRule: "",
    viewRule: "",
    createRule: "",
    updateRule: "",
    deleteRule: "",
    schema: [
      { name: "property", type: "relation", required: true, options: { collectionId: properties.id, maxSelect: 1 } },
      { name: "month", type: "text", required: true },
      { name: "green_days", type: "number" },
      { name: "total_days", type: "number" },
      { name: "score", type: "number" },
      { name: "rebate_eligible", type: "bool" }
    ]
  });
  dao.saveCollection(compliance_scores);

}, (db) => {
  const dao = new Dao(db);
  dao.deleteCollection(dao.findCollectionByNameOrId("compliance_scores"));
  dao.deleteCollection(dao.findCollectionByNameOrId("audit_logs"));
  dao.deleteCollection(dao.findCollectionByNameOrId("properties"));
  dao.deleteCollection(dao.findCollectionByNameOrId("scanners"));
  dao.deleteCollection(dao.findCollectionByNameOrId("workers"));
  dao.deleteCollection(dao.findCollectionByNameOrId("wards"));
})
