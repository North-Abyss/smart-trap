migrate((db) => {
  const dao = new Dao(db);
  const collection = dao.findCollectionByNameOrId("properties00000"); // Or find by name if you prefer

  // Check if we found the collection successfully
  if (!collection) {
    console.log("Could not find properties collection");
    return;
  }

  // Add owner_name field
  collection.schema.addField(new SchemaField({
    "system": false,
    "id": "prop_owner_name",
    "name": "owner_name",
    "type": "text",
    "required": false,
    "unique": false,
    "options": {
      "min": null,
      "max": null,
      "pattern": ""
    }
  }));

  // Add phone_number field
  collection.schema.addField(new SchemaField({
    "system": false,
    "id": "prop_phone_number",
    "name": "phone_number",
    "type": "text",
    "required": false,
    "unique": false,
    "options": {
      "min": null,
      "max": null,
      "pattern": ""
    }
  }));

  return dao.saveCollection(collection);
}, (db) => {
  const dao = new Dao(db);
  const collection = dao.findCollectionByNameOrId("properties00000");

  if (!collection) {
    return;
  }

  collection.schema.removeField("prop_owner_name");
  collection.schema.removeField("prop_phone_number");

  return dao.saveCollection(collection);
});
