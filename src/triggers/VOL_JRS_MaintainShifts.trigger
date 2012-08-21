trigger VOL_JRS_MaintainShifts on Volunteer_Job_Recurrence_Schedule__c (after insert, after undelete, after update, before delete) {
    
    if (trigger.isInsert || trigger.isUpdate || trigger.isUnDelete) {
        VOL_BATCH_Recurrence.ProcessListJRS(trigger.new, true);  
    }
    
    if (trigger.isDelete) {
        VOL_BATCH_Recurrence.DeleteListJRS(trigger.old);        
    }

}