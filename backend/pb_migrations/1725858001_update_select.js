migrate((db) => {
  const dao = new Dao(db);

  const scanners = dao.findCollectionByNameOrId("scanners");
  const statusField = scanners.schema.getFieldByName("status");
  statusField.options.maxSelect = 1;
  dao.saveCollection(scanners);

  const properties = dao.findCollectionByNameOrId("properties");
  const propTypeField = properties.schema.getFieldByName("property_type");
  propTypeField.options.maxSelect = 1;
  dao.saveCollection(properties);

}, (db) => {
  // down
})
