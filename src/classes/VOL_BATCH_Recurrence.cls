global with sharing class VOL_BATCH_Recurrence implements Database.Batchable<Sobject>, Schedulable {

	private string strSoql { get; set; }

    /*******************************************************************************************************
	* @description This constructor is needed to allow this class to be schedulable.
	*/
    global VOL_BATCH_Recurrence() { }
    
    /*******************************************************************************************************
	* @description Standard schedulable execute method.  This simply gets the batch started when called from 
	* a scheduled job.  
	*/    
    global void execute(SchedulableContext sc) {
		database.executebatch(this);                 
    }
    
    /*******************************************************************************************************
	* @description Standard batch start method.    
	*/    
    global Database.QueryLocator start(Database.BatchableContext bc) { 
    	Date dt = system.today();
    	strSoql = 'select Id, Name, Days_of_Week__c, Desired_Number_of_Volunteers__c, Duration__c, Description__c, ' +
    		' Schedule_End_Date__c, Schedule_Start_Date_Time__c, Volunteer_Job__c, Weekly_Occurence__c ' +
    		' from Volunteer_Job_Recurrence_Schedule__c where ' +
    		' Schedule_End_Date__c = null or Schedule_End_Date__c > :dt';
        return Database.getQueryLocator(strSoql);
    }

    /*******************************************************************************************************
	* @description The main batch execute method.  
	*/
    global void execute(Database.BatchableContext BC, List<Sobject> listSObj) {
    	ProcessListJRS(listSObj, false);	
    }

    /*******************************************************************************************************
	* @description The standard batch finish method.  
	*/      
    global void finish(Database.BatchableContext bc) {

    }

	// for the specified JRS's, delete all shifts that have no committed & completed hours.
	// called from the After Delete JRS trigger.
	public static void DeleteListJRS(list<Volunteer_Job_Recurrence_Schedule__c> listJRS) {
		
		// get a set of the JRS ID's for querying
		set<ID> setJRSId = new set<ID>();
		for (Volunteer_Job_Recurrence_Schedule__c jrs : listJRS) {
			setJRSId.add(jrs.Id);
		}
		
		// get all shifts associated with these JRS's that we should delete
		list<Volunteer_Shift__c> listShift = new list<Volunteer_Shift__c>();
		listShift = [select Id, Total_Volunteers__c from Volunteer_Shift__c  
			where ((Total_Volunteers__c = null or Total_Volunteers__c = 0) and 
				Job_Recurrence_Schedule__c in : setJRSId)];
		
		delete listShift;
	}

	// given a list of recurring schedules, does all the work to delete any shifts that
	// no longer match, and creates new shifts into the future.
	// called from both the JRS trigger (when the user modifies a specific JRS),
	// as well as from the batch process to reprocess all JRS's.
	// fReviewAllShifts parameter specifies whether called from the trigger on JRS's, in
	// which case we should review all shifts under the JRS, or from the scheduled batch,
	// in which case we only need to be looking to add additional shifts in the future.
	public static void ProcessListJRS(list<Volunteer_Job_Recurrence_Schedule__c> listJRS, boolean fReviewAllShifts) {
		
		// get a set of the JRS ID's for querying
		set<ID> setJRSId = new set<ID>();
		for (Volunteer_Job_Recurrence_Schedule__c jrs : listJRS) {
			setJRSId.add(jrs.Id);
		}
		
		// get all shifts associated with these JRS's
		list<Volunteer_Shift__c> listShift = new list<Volunteer_Shift__c>();
		listShift = [select Id, Start_Date_Time__c, Job_Recurrence_Schedule__c, 
				Total_Volunteers__c, Desired_Number_of_Volunteers__c, Volunteer_Job__c, Description__c, System_Note__c
			from Volunteer_Shift__c where Job_Recurrence_Schedule__c in : setJRSId 
			order by Start_Date_Time__c];
			
		// construct a map of JRS to its associated shifts
		map<ID, list<Volunteer_Shift__c>> mapJRSIdShift = new map<ID, list<Volunteer_Shift__c>>();
		
		// put the Shifts on each JRS's list
		for (Volunteer_Shift__c shift : listShift) {			
			list<Volunteer_Shift__c> listJRSShift = mapJRSIdShift.get(shift.Job_Recurrence_Schedule__c);
			if (listJRSShift == null) listJRSShift = new list<Volunteer_Shift__c>();
			listJRSShift.add(shift);
			mapJRSIdShift.put(shift.Job_Recurrence_Schedule__c, listJRSShift);				
		}

		// lists to hold all the shifts we need to create, delete, and update
		list<Volunteer_Shift__c> listShiftNew = new list<Volunteer_Shift__c>();
		list<Volunteer_Shift__c> listShiftDelete = new list<Volunteer_Shift__c>();
		list<Volunteer_Shift__c> listShiftUpdate = new list<Volunteer_Shift__c>();
		
		// now look at each JRS's shifts, and decide what to do, potentially adding more shifts
		for (Volunteer_Job_Recurrence_Schedule__c jrs : listJRS) {
			list<Volunteer_Shift__c> listJRSShift = mapJRSIdShift.get(jrs.Id);
			if (listJRSShift == null) listJRSShift = new list<Volunteer_Shift__c>(); 
			ProcessJRS(jrs, listJRSShift, listShiftNew, listShiftDelete, listShiftUpdate, fReviewAllShifts);
		}
		
		// commit the work
		if (listShiftNew.size() > 0)
			insert listShiftNew;
		if (listShiftDelete.size() > 0)
			delete listShiftDelete;		
		if (listShiftUpdate.size() > 0)
			update listShiftUpdate;

		// get all Volunteer Recurring Schedules associated with these JRS's
		list<Volunteer_Recurrence_Schedule__c> listVRS = new list<Volunteer_Recurrence_Schedule__c>();
		listVRS = [select Id, Contact__c, Schedule_Start_Date_Time__c, Schedule_End_Date__c, Duration__c,
			Weekly_Occurence__c, Days_Of_Week__c, Volunteer_Job_Recurrence_Schedule__c
			from Volunteer_Recurrence_Schedule__c where Volunteer_Job_Recurrence_Schedule__c in : setJRSId 
			order by Schedule_Start_Date_Time__c];

		// construct a map of JRS to its associated VRS's
		map<ID, list<Volunteer_Recurrence_Schedule__c>> mapJRSIdVRS = new map<ID, list<Volunteer_Recurrence_Schedule__c>>();
		
		// put the VRS's on each JRS's list
		for (Volunteer_Recurrence_Schedule__c vrs : listVRS) {			
			list<Volunteer_Recurrence_Schedule__c> listVRSforJRS = mapJRSIdVRS.get(vrs.Volunteer_Job_Recurrence_Schedule__c);
			if (listVRSforJRS == null) listVRSforJRS = new list<Volunteer_Recurrence_Schedule__c>();
			listVRSforJRS.add(vrs);
			mapJRSIdVRS.put(vrs.Volunteer_Job_Recurrence_Schedule__c, listVRSforJRS);				
		}

		list<Volunteer_Hours__c> listHoursNew = new list<Volunteer_Hours__c>();
		for (Volunteer_Shift__c shift : listShiftNew) {
			list<Volunteer_Recurrence_Schedule__c> listVRSforJRS = mapJRSIdVRS.get(shift.Job_Recurrence_Schedule__c);
			AssignVRSHours(shift, listVRSforJRS, listHoursNew);
		}
		if (listHoursNew.size() > 0)
			insert listHoursNew;
	}

	// Process a single recurrence schedule, adding new shifts to the passed in list.
	// fReviewAllShifts specifies whether we should verify old shifts still match the schedule.
	private static void ProcessJRS(Volunteer_Job_Recurrence_Schedule__c jrs, 
		list<Volunteer_Shift__c> listJRSShift, // assumes ordered by ascending date
		list<Volunteer_Shift__c> listShiftNew, 
		list<Volunteer_Shift__c> listShiftDelete,
		list<Volunteer_Shift__c> listShiftUpdate,
		boolean fReviewAllShifts ) {
	
		// assume custom setting to specify how far into future shifts should populate to.
		Date dtStop = system.today();
		integer nMonths = 12;
		if (VOL_SharedCode.VolunteersSettings.Recurring_Job_Future_Months__c != null) {
			nMonths = integer.valueOf(VOL_SharedCode.VolunteersSettings.Recurring_Job_Future_Months__c); 
		}
		dtStop = dtStop.addMonths(nMonths);
		
		// create a map of date to shift, for quick lookups.
		map<Date, Volunteer_Shift__c> mapDtShift = new map<Date, Volunteer_Shift__c>();
		for (Volunteer_Shift__c shift: listJRSShift) {
			mapDtShift.put(shift.Start_Date_Time__c.date(), shift);
		}
		
		// if fReviewAllShifts, we'll start at the JRS's start date.
		// if !fReviewAllShifts, we'll just start after the latest shift (if we have one).
		Date dtLast;
		if (fReviewAllShifts) {
			dtLast = jrs.Schedule_Start_Date_Time__c.date().addDays(-1);  // -1, so we'll create on start date if appropriate.
		} else if (listJRSShift.size() > 0) {
			dtLast = date.valueOf(listJRSShift[listJRSShift.size() - 1].Start_Date_Time__c);
		} else {
			dtLast = system.Today();			
		}
		
		while (dtLast < dtStop) {
			dtLast = dtNextDateForJRS(jrs, dtLast);
			
			if (dtLast == null) 
				break;
			
			// see if we already have a shift for that date
			Volunteer_Shift__c shiftExisting = mapDtShift.get(dtLast);
			
			// if we have the shift, update its Job, time and duration
			if (shiftExisting != null) {
				shiftExisting.Duration__c = jrs.Duration__c;
				shiftExisting.Start_Date_Time__c = datetime.newInstance(dtLast, jrs.Schedule_Start_Date_Time__c.time());
				if (jrs.Desired_Number_of_Volunteers__c != null)
					shiftExisting.Desired_Number_of_Volunteers__c = jrs.Desired_Number_of_Volunteers__c;
				if (jrs.Description__c != null)
					shiftExisting.Description__c = jrs.Description__c;
				listShiftUpdate.add(shiftExisting);	
				// also remove the shift from our map, so we'll end up with those to delete.
				mapDtShift.remove(dtLast);			
			} else {
				Volunteer_Shift__c shift = new Volunteer_Shift__c();
				shift.System_Note__c = 'Auto-created for Job Recurrence Schedule.';
				shift.Description__c = jrs.Description__c;
				shift.Job_Recurrence_Schedule__c = jrs.Id;
				shift.Duration__c = jrs.Duration__c;
				shift.Volunteer_Job__c = jrs.Volunteer_Job__c;				
				shift.Start_Date_Time__c = datetime.newInstance(dtLast, jrs.Schedule_Start_Date_Time__c.time());
				shift.Desired_Number_of_Volunteers__c = jrs.Desired_Number_of_Volunteers__c;
				listShiftNew.add(shift);
			}
		}
		
		// we've finished identifying shifts to update and those to create.
		// now figure out if there are any to delete or remove from the jrs.
		if (fReviewAllShifts) {
			for (Volunteer_Shift__c shift: mapDtShift.values()) {
				if (shift.Total_Volunteers__c > 0) {
					shift.Job_Recurrence_Schedule__c = null;
					shift.System_Note__c += ' Removed from Job Recurrence Schedule: ' + jrs.Name + '.';					
					listShiftUpdate.add(shift);	
				} else {
					listShiftDelete.add(shift);
				}
			}			
		}		
		
		// we don't commit the shifts, leaving the caller to do it.		
	}
	
	// return the next scheduled date for the given schedule, from the passed in date (exclusive).
	// DOES NOT assume the passed in date is valid for the schedule.
	private static Date dtNextDateforJRS(Volunteer_Job_Recurrence_Schedule__c jrs, Date dt) {
		
		// strategy is to find the first valid nday, and then find its next nweek.
		Date dtFirst = dtFirstOcurrenceInWeek(jrs, dt);
		boolean fAlternate = true;	// we assume the first date passed in is a valid week.
		boolean fValidWeek = validWeek(jrs, dtFirst, fAlternate);  // remember if current date is on valid week.
		
		// if we aren't on a valid week we want to skip to the first nday of the next week.		
		if (!fValidWeek) {
			dt = dtFirst.addDays(6);
		}
		
		integer nDay = nDayOfWeek(dt);
		list<boolean> listWhichDays = WhichDaysJRS(jrs);
		
		for (integer n = nDay; true; ) {
			n++;
			dt = dt.addDays(1);
			
			if (n == 8) {
				n = 1;
				fAlternate = !fAlternate;
			}
			
			if (!listWhichDays[n]) {
				continue;
			}
			
			// we've found the next day.
			// now find the correct week.
			if ((fValidWeek && n > nDay) || validWeek(jrs, dt, fAlternate)) {
				break;
			}
			integer cweeks = cWeeksNext(jrs, dt, fAlternate);
			dt = dt.addDays(cweeks * 7);
			break;
			
			// skip a week.
			//n--; // so that the loop will put us back to same nday
			//dt = dt.addDays(6); // so the loop will put us a full week ahead.
		}
		
		return dt;
		
		/****************************
		integer nDay = nDayOfWeek(dt);
		list<boolean> listWhichDays = WhichDaysJRS(jrs);
		integer cDaysToAdd = 0;
		integer cWeeksToAdd = 0;
		
		// can't assume passed in date is valid for our schedule.
		// so make sure we start on the correct week.
		integer nweek = nWeekOfDate(dt);
		list<boolean> listWhichWeeks = WhichWeeksJRS(jrs);
		if (!listWhichWeeks[nweek] && 
			!jrs.Weekly_Occurence__c.contains('Every') &&
			!jrs.Weekly_Occurence__c.contains('Alternate')) {
			dt = dt.addDays(7 - nDay);
			nDay = 7;
		}			
		
		for (integer n = nDay + 1; true; n++) {
			if (n == 8) {
				n = 0;  // will get reset to one on next iteration
				cWeeksToAdd += cWeeksNext(jrs, dt);
				continue;
			}
			if (listWhichDays[n]) {
				cDaysToAdd = n - nDay;
				break;
			}			
		}
		system.debug('cDaysToAdd: ' + cDaysToAdd + ' cWeeksToAdd: ' + cWeeksToAdd);
		return dt.addDays(cDaysToAdd + (cWeeksToAdd * 7));		
*****************/		
	}
	
	// returns an array of booleans for which days are on the schedule.
	// note that you should index by nDay (ie, Mon = index 2).
	private static list<boolean> WhichDaysJRS (Volunteer_Job_Recurrence_Schedule__c jrs) {
		list<boolean> listWhichDays = new boolean[8];
		listWhichDays[0] = false;
		listWhichDays[1] = jrs.Days_of_Week__c.contains('Sunday');
		listWhichDays[2] = jrs.Days_of_Week__c.contains('Monday');
		listWhichDays[3] = jrs.Days_of_Week__c.contains('Tuesday');
		listWhichDays[4] = jrs.Days_of_Week__c.contains('Wednesday');
		listWhichDays[5] = jrs.Days_of_Week__c.contains('Thursday');
		listWhichDays[6] = jrs.Days_of_Week__c.contains('Friday');
		listWhichDays[7] = jrs.Days_of_Week__c.contains('Saturday');
		return listWhichDays; 
	}

	// returns an array of booleans for which weeks are on the schedule.
	// note that you should index by nWeek (ie, first = index 1).
	private static list<boolean> WhichWeeksJRS(Volunteer_Job_Recurrence_Schedule__c jrs) {
		list<boolean> listWhichWeeks = new boolean[6];
		listWhichWeeks[0] = false;
		listWhichWeeks[1] = jrs.Weekly_Occurence__c.contains('1st');
		listWhichWeeks[2] = jrs.Weekly_Occurence__c.contains('2nd');
		listWhichWeeks[3] = jrs.Weekly_Occurence__c.contains('3rd');
		listWhichWeeks[4] = jrs.Weekly_Occurence__c.contains('4th');
		listWhichWeeks[5] = jrs.Weekly_Occurence__c.contains('5th');
		return listWhichWeeks;
	}

	// returns an array of booleans for which days are on the schedule.
	// note that you should index by nDay (ie, Mon = index 2).
	private static list<boolean> WhichDaysVRS (Volunteer_Recurrence_Schedule__c vrs) {
		list<boolean> listWhichDays = new boolean[8];
		listWhichDays[0] = false;
		listWhichDays[1] = vrs.Days_of_Week__c.contains('Sunday');
		listWhichDays[2] = vrs.Days_of_Week__c.contains('Monday');
		listWhichDays[3] = vrs.Days_of_Week__c.contains('Tuesday');
		listWhichDays[4] = vrs.Days_of_Week__c.contains('Wednesday');
		listWhichDays[5] = vrs.Days_of_Week__c.contains('Thursday');
		listWhichDays[6] = vrs.Days_of_Week__c.contains('Friday');
		listWhichDays[7] = vrs.Days_of_Week__c.contains('Saturday');
		return listWhichDays; 
	}

	// returns an array of booleans for which weeks are on the schedule.
	// note that you should index by nWeek (ie, first = index 1).
	private static list<boolean> WhichWeeksVRS(Volunteer_Recurrence_Schedule__c vrs) {
		list<boolean> listWhichWeeks = new boolean[6];
		listWhichWeeks[0] = false;
		listWhichWeeks[1] = vrs.Weekly_Occurence__c.contains('1st');
		listWhichWeeks[2] = vrs.Weekly_Occurence__c.contains('2nd');
		listWhichWeeks[3] = vrs.Weekly_Occurence__c.contains('3rd');
		listWhichWeeks[4] = vrs.Weekly_Occurence__c.contains('4th');
		listWhichWeeks[5] = vrs.Weekly_Occurence__c.contains('5th');
		return listWhichWeeks;
	}

	// given the current date, return the first date in that week that should be scheduled		
	private static Date dtFirstOcurrenceInWeek(Volunteer_Job_Recurrence_Schedule__c jrs, Date dt) {
		list<boolean> listWhichDays = WhichDaysJRS(jrs);
		integer nday = nDayOfWeek(dt);
		integer n;
		for (n = 1; n < nday; n++) {
			if (listWhichDays[n])
				break;
		}		
		return dt.addDays(n - nday);
	} 	
		
	// return the occurrence of the day in the month (ie, 1 first - 5 fifth)
	private static integer nWeekOfDate(Date dt) {
		return ((dt.day() - 1) / 7) + 1;
	}
	
	// return the date of the nth day in the nth week of the provided month and year
	// ie, return the 2nd Friday of Feb 2012.  
	// nday: 1 - 7 (implying Sun - Sat)
	// nweek: 1 - 5 (implying first - fifth)
	private static Date dtNthDay(integer year, integer month, integer nday, integer nweek) {
		Date dtStartMonth = date.NewInstance(year, month, 1);
		integer ndayStartMonth = nDayOfWeek(dtStartMonth);
		integer day;
		if (nday >= ndayStartMonth) {
			day = nday - ndayStartMonth + 1 + ((nweek-1) * 7);
		} else {
			day = (nweek * 7) - (ndayStartMonth - nday - 1);			
		}
		return Date.NewInstance(year, month, day);		
	} 
	
	// returns an integer 1 - 7, represening the day of the week.
	private static integer nDayOfWeek(Date dt) {
		return (dt.toStartOfWeek().daysBetween(dt) + 1);		
	}
	// returns whether the nweek of the specified date is valid for this schedule
	private static boolean validWeek(Volunteer_Job_Recurrence_Schedule__c jrs, Date dt, boolean fAlternate) {
		integer nweek = nWeekOfDate(dt);
		list<boolean> listWhichWeeks = WhichWeeksJRS(jrs);
		if (listWhichWeeks[nweek] || jrs.Weekly_Occurence__c.contains('Every'))
			return true;
		else if (fAlternate && jrs.Weekly_Occurence__c.contains('Alternate'))
			return true;
		else
			return false;
	}			
		
	// returns how many weeks until the next recurrence on the schedule
	private static integer cWeeksNext(Volunteer_Job_Recurrence_Schedule__c jrs, Date dt, boolean fAlternate) {
		if (jrs.Weekly_Occurence__c == null) {
			// treat empty as every week, so we avoid infinite loops.
			return 1;
		} else if (jrs.Weekly_Occurence__c.contains('Every')) { 
			return 1;
		} else if (jrs.Weekly_Occurence__c.contains('Alternate')) {
			return fAlternate ? 2 : 1;
		} else {
			list<boolean> listWhichWeeks = WhichWeeksJRS(jrs);
			integer nweek = nWeekOfDate(dt);
			integer cweeks = 0;
			
			for (integer n = nweek + 1; true; n++) {
				if (n == 6) {
					Date dtEndOfMonth = dt.toStartOfMonth().addMonths(1).addDays(-1);
					cweeks = (dt.daysBetween(dtEndOfMonth) / 7) + 1;
					nweek = 1;
					n = 0;
					continue;
				}
				if (listWhichWeeks[n]) { 
					system.debug ('n:' + n + ' nweek:' + nweek + ' cweeks:' + cweeks);
					return (n - nweek + cweeks);
				}
			}
		}
		return 0;
	}
	
	private static void	AssignVRSHours(
		Volunteer_Shift__c shift, 
		list<Volunteer_Recurrence_Schedule__c> listVRS, 
		list<Volunteer_Hours__c> listHoursNew
		) {

		// Strategy:
		// for the given shift, go through the list of VRS's
		// and create hours for the ones that match.
		
		integer cDesiredVols = 100;
		if (shift.Desired_Number_of_Volunteers__c != null) 
			cDesiredVols = integer.valueOf(shift.Desired_Number_of_Volunteers__c);
		Date dtShift = shift.Start_Date_Time__c.Date();
		integer nweek = nWeekOfDate(dtShift);
		integer nday = nDayOfWeek(dtShift);
		
		for (Volunteer_Recurrence_Schedule__c vrs : listVRS) {
		
			// exit if we've filled all the slots.
			if (cDesiredVols <= 0) 
				break;
		
			list<boolean> listWhichDays = WhichDaysVRS(vrs);
			list<boolean> listWhichWeeks = WhichWeeksVRS(vrs);
			
			if ((listWhichWeeks[nweek] || vrs.Weekly_Occurence__c.contains('Every')) && 
				listWhichDays[nday] &&
				dtShift >= vrs.Schedule_Start_Date_Time__c.Date() &&
				(vrs.Schedule_End_Date__c == null || vrs.Schedule_End_Date__c > dtShift)) {
				Volunteer_Hours__c hr = new Volunteer_Hours__c();
				hr.Comments__c = 'Auto-created for Volunteer Recurrence Schedule.';
				hr.Contact__c = vrs.Contact__c;
				hr.Hours_Worked__c = vrs.Duration__c;
				hr.Number_of_Volunteers__c = 1;
				//hr.Shift_Start_Date_Time__c = datetime.newInstance(dtShift, vrs.Schedule_Start_Date_Time__c.time());
				hr.Start_Date__c = dtShift;
				hr.End_Date__c = dtShift;
				hr.Status__c = 'confirmed';	// UNDONE: add to VRS or custom setting?
				hr.Volunteer_Job__c = shift.Volunteer_Job__c;
				hr.Volunteer_Shift__c = shift.Id;	
				hr.Volunteer_Recurrence_Schedule__c = vrs.Id;			
				listHoursNew.add(hr);
				cDesiredVols--;
			}			 		
		}
		
		// we let the caller commit the new hours to the db.		
	}

    //==================== TEST METHOD(s) ======================================
    global static testmethod void TestNextDateforJRS() {

		// create test data
        Campaign cmp = new Campaign(recordtypeid=VOL_SharedCode.recordtypeIdVolunteersCampaign, 
        	name='Job Calendar Test Campaign', IsActive=true);
        insert cmp;
        Volunteer_Job__c job = new Volunteer_Job__c(name='Job1', campaign__c=cmp.Id);
        insert job;
        Volunteer_Shift__c shift = new Volunteer_Shift__c(Volunteer_Job__c=job.Id, Duration__c=1, 
        	Start_Date_Time__c=date.valueOf('2012-1-1')	);  // 1/1/2012 was a Sunday
        insert shift;
        Volunteer_Job_Recurrence_Schedule__c jrs = new Volunteer_Job_Recurrence_Schedule__c(Volunteer_Job__c = job.Id);
		jrs.Days_of_Week__c = 'Monday;Wednesday;Friday';
		jrs.Duration__c = 1;
		jrs.Schedule_Start_Date_Time__c = datetime.parse('1/1/2012 10:00 AM');
		jrs.Weekly_Occurence__c = 'Every';
		jrs.Desired_Number_of_Volunteers__c = 5;
		insert jrs;
		
		// test Day of Week
		system.assertEquals(1, nDayOfWeek(date.valueOf('2012-1-1')));
		system.assertEquals(7, nDayOfWeek(date.valueOf('2012-1-7')));
		system.assertEquals(3, nDayOfWeek(date.valueOf('2012-1-31')));
		system.assertEquals(4, nDayOfWeek(date.valueOf('2012-2-1')));
		system.assertEquals(4, nDayOfWeek(date.valueOf('2012-2-29')));
		
		// test dtNthDay
		system.assertEquals(date.valueOf('2012-1-1'), dtNthDay(2012, 1, 1, 1));
		system.assertEquals(date.valueOf('2012-1-7'), dtNthDay(2012, 1, 7, 1));
		system.assertEquals(date.valueOf('2012-1-8'), dtNthDay(2012, 1, 1, 2));
		system.assertEquals(date.valueOf('2012-1-31'), dtNthDay(2012, 1, 3, 5));
		system.assertEquals(date.valueOf('2012-2-3'), dtNthDay(2012, 2, 6, 1));		
		system.assertEquals(date.valueOf('2012-2-6'), dtNthDay(2012, 2, 2, 1));
		system.assertEquals(date.valueOf('2012-2-27'), dtNthDay(2012, 2, 2, 4));
		system.assertEquals(date.valueOf('2012-2-29'), dtNthDay(2012, 2, 4, 5));
		system.assertEquals(date.valueOf('2012-2-18'), dtNthDay(2012, 2, 7, 3));
		
		// test Every week.
		Date dtNext =  dtNextDateforJRS(jrs, date.valueOf(shift.Start_Date_Time__c));
		system.assertEquals(1, cWeeksNext(jrs, dtNext, false));		
		system.assertEquals(date.valueOf('2012-1-2'), dtNext); 	
		dtNext =  dtNextDateforJRS(jrs, dtNext);
		system.assertEquals(date.valueOf('2012-1-4'), dtNext); 	
		dtNext =  dtNextDateforJRS(jrs, dtNext);
		system.assertEquals(date.valueOf('2012-1-6'), dtNext); 	
		dtNext =  dtNextDateforJRS(jrs, dtNext);
		system.assertEquals(date.valueOf('2012-1-9'), dtNext); 	
		
		// test Alternate weeks.
		jrs.Weekly_Occurence__c = 'Alternate';
		update jrs;
		system.assertEquals(2, cWeeksNext(jrs, dtNext, true));		
		dtNext =  dtNextDateforJRS(jrs, dtNext);
		system.assertEquals(date.valueOf('2012-1-11'), dtNext); 	
		dtNext =  dtNextDateforJRS(jrs, dtNext);
		system.assertEquals(date.valueOf('2012-1-13'), dtNext); 	
		dtNext =  dtNextDateforJRS(jrs, dtNext);
		system.assertEquals(date.valueOf('2012-1-23'), dtNext); 
		
		// test figuring out occurrence of day in month
		system.assertEquals(1, nWeekOfDate(date.valueOf('2012-1-1')));
		system.assertEquals(1, nWeekOfDate(date.valueOf('2012-1-7')));
		system.assertEquals(2, nWeekOfDate(date.valueOf('2012-1-8')));
		system.assertEquals(5, nWeekOfDate(date.valueOf('2012-1-29')));
		system.assertEquals(5, nWeekOfDate(date.valueOf('2012-1-31')));
		system.assertEquals(1, nWeekOfDate(date.valueOf('2012-2-1')));
		system.assertEquals(1, nWeekOfDate(date.valueOf('2012-2-4')));
		system.assertEquals(1, nWeekOfDate(date.valueOf('2012-2-5')));
		system.assertEquals(5, nWeekOfDate(date.valueOf('2012-2-29')));
		system.assertEquals(1, nWeekOfDate(date.valueOf('2012-2-6')));
		
		// test Nth week of Month
		jrs.Weekly_Occurence__c = '3rd';
		update jrs;
		list<boolean> listWhichWeeks = WhichWeeksJRS(jrs);
		system.assertEquals(false, listWhichWeeks[0]);
		system.assertEquals(false, listWhichWeeks[1]);
		system.assertEquals(false, listWhichWeeks[2]);
		system.assertEquals(true, listWhichWeeks[3]);
		system.assertEquals(false, listWhichWeeks[4]);
		system.assertEquals(false, listWhichWeeks[5]);

		system.assertEquals(2, cWeeksNext(jrs, date.valueOf('2012-1-1'), false));		
		system.assertEquals(2, cWeeksNext(jrs, date.valueOf('2012-1-7'), false));		
		system.assertEquals(1, cWeeksNext(jrs, date.valueOf('2012-1-8'), false));		
		system.assertEquals(1, cWeeksNext(jrs, date.valueOf('2012-1-14'), false));		
		system.assertEquals(5, cWeeksNext(jrs, date.valueOf('2012-1-15'), false));		

		dtNext =  dtNextDateforJRS(jrs, date.valueOf('2012-1-7')); 
		system.assertEquals(date.valueOf('2012-1-16'), dtNext); 

		jrs.Days_of_Week__c = 'Monday';
		update jrs;
		dtNext =  dtNextDateforJRS(jrs, date.valueOf('2012-4-16'));
		system.assertEquals(date.valueOf('2012-5-21'), dtNext); 

		jrs.Days_of_Week__c = 'Wednesday';
		update jrs;
		dtNext =  dtNextDateforJRS(jrs, date.valueOf('2012-4-18'));
		system.assertEquals(date.valueOf('2012-5-16'), dtNext); 

		jrs.Weekly_Occurence__c = '1st';
		jrs.Days_of_Week__c = 'Monday';
		update jrs;
		dtNext =  dtNextDateforJRS(jrs, date.valueOf('2012-2-6'));
		system.assertEquals(date.valueOf('2012-3-5'), dtNext); 
		
		jrs.Weekly_Occurence__c = '2nd;4th;';
		jrs.Days_of_Week__c = 'Sunday';
		update jrs;
		dtNext =  dtNextDateforJRS(jrs, date.valueOf('2012-8-1'));
		system.assertEquals(date.valueOf('2012-8-12'), dtNext);  
		
		// test batch calculations
       	VOL_BATCH_Recurrence r = new VOL_BATCH_Recurrence();
    	r.execute(null);	
		
		// test deleting the JRS
		delete jrs;
		
    }   

}