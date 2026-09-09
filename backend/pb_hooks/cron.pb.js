cronAdd("monthly_compliance", "0 0 1 * *", () => {
    console.log("Running monthly compliance score calculation...");
    
    // Calculate previous month
    const now = new Date();
    let year = now.getFullYear();
    let month = now.getMonth(); // 0-indexed, so this is previous month if now is 1st of month. If January (0), it becomes 0, wait, it's safer to subtract 1 month.
    
    const prevMonthDate = new Date(now.getFullYear(), now.getMonth() - 1, 1);
    const targetMonthStr = `${prevMonthDate.getFullYear()}-${String(prevMonthDate.getMonth() + 1).padStart(2, '0')}`;
    
    // Get start and end of previous month
    const startOfMonth = new Date(prevMonthDate.getFullYear(), prevMonthDate.getMonth(), 1).toISOString().replace('T', ' ').substring(0, 19) + "Z";
    const endOfMonth = new Date(prevMonthDate.getFullYear(), prevMonthDate.getMonth() + 1, 0, 23, 59, 59).toISOString().replace('T', ' ').substring(0, 19) + "Z";
    
    // Fetch all audit logs for the previous month
    const logs = $app.dao().findRecordsByFilter(
        "audit_logs",
        `timestamp >= '${startOfMonth}' && timestamp <= '${endOfMonth}'`
    );
    
    // Aggregate by property
    const propertyStats = {}; // { "propertyId": { green: 0, total: 0 } }
    
    for (let log of logs) {
        const propId = log.get("property");
        const status = log.get("status"); // true = green, false = red
        
        if (!propertyStats[propId]) {
            propertyStats[propId] = { green: 0, total: 0 };
        }
        
        propertyStats[propId].total++;
        if (status) {
            propertyStats[propId].green++;
        }
    }
    
    // Calculate scores and insert
    const complianceScores = $app.dao().findCollectionByNameOrId("compliance_scores");
    
    for (const [propId, stats] of Object.entries(propertyStats)) {
        const score = (stats.green / stats.total) * 100;
        const eligible = score >= 80;
        
        const record = new Record(complianceScores);
        record.set("property", propId);
        record.set("month", targetMonthStr);
        record.set("green_days", stats.green);
        record.set("total_days", stats.total);
        record.set("score", score);
        record.set("rebate_eligible", eligible);
        
        $app.dao().saveRecord(record);
    }
    
    console.log(`Compliance calculation completed for ${targetMonthStr}. Processed ${Object.keys(propertyStats).length} properties.`);
});
