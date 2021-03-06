/**
* @author - Murugesh Naidu, Veeva Systems Inc
* @className - CLMVisibilityManager.cls
* @description - Controller class for CLM Visibility Manager
* @createdate - March 18th, 2012
*
*/

public class CLMVisibilityManager {

    public SelectOption[] selectedCLMPrezis { get; set; }
    public SelectOption[] selectedCLMPrezisBeforeChange { get; set; }
    public SelectOption[] originallyAvailablePrezis { get; set; }
    public SelectOption[] allCLMPresentations { get; set; }
    public Set<ID> unChangedPrezisSet { get; set; }
    public String message { get; set; }
    public List<CLM_Presentation_vod__c> userAvailablePreziList;
    public List<CLM_Visibility_Manager_Transaction__c> transactionList;
    public Set<ID> newlyVisibleCLMIDs = new Set<ID>();
    public Set<ID> newlyInvisibleCLMIDs = new Set<ID>();
    public Boolean CLEAR_CACHE  { get; set; }
    public Boolean RENDER_PANEL  { get; set; }
    public Boolean HAS_ERROR  { get; set; }
    public Boolean IS_ADMIN  { get; set; }
    public Boolean HANDLE_KEY_MESSAGE_DOWNLOADS = true;
    public String CLR_CACHE_STR  ;
    
    public String getCLR_CACHE_STR(){
    	return CLR_CACHE_STR;
    }
    public void setCLR_CACHE_STR(String x){
    	CLR_CACHE_STR = x;
    	CLEAR_CACHE = Boolean.valueOf(x);
    }
    
    /*
    * @methodDescription - Constructor - Populates the Available (Non-accessible) & Visible lists
    * of  <code>Clm_Presentation_vod__c</code>
    */

    public CLMVisibilityManager() {
    	CLEAR_CACHE = false;
    	HAS_ERROR = false;
		Profile loggedInProfile = [SELECT Id, Name, PermissionsModifyAllData, PermissionsViewAllData 
									FROM Profile 
									WHERE ID = :UserInfo.getProfileId()];   
		
		if(loggedInProfile!=null && 
				(loggedInProfile.PermissionsModifyAllData || loggedInProfile.PermissionsViewAllData )){
			IS_ADMIN = true;
			HAS_ERROR = true;
    		ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR,CLMVisibilityManagerUtil.CLM_PREZI_EXCEPTION_ADMIN_NOT_ALLOWED)) ;
		}
			
        userAvailablePreziList = (List<CLM_Presentation_vod__c>) new UserSpecificOps().getUserVisiblePrezis(false);
        selectedCLMPrezis = CLMVisibilityManagerUtil.convertToSelectOptions(userAvailablePreziList);
        if(selectedCLMPrezis!=null){
	        originallyAvailablePrezis = new List<SelectOption> ();
	        originallyAvailablePrezis.addAll(selectedCLMPrezis);
	        selectedCLMPrezisBeforeChange = new List<SelectOption> ();
	        selectedCLMPrezisBeforeChange.addAll(selectedCLMPrezis);
        }
        allCLMPresentations =    getALLAvailableCLMPrezis(false);
        System.debug('selectedCLMPrezis = ' + selectedCLMPrezis);
        System.debug('originallyAvailablePrezis = ' + originallyAvailablePrezis);
        System.debug('allCLMPresentations = ' + allCLMPresentations);
        transactionList = new List<CLM_Visibility_Manager_Transaction__c>();
    }

	/*
	* @methodDescription: Updates visibility of  <code>Clm_Presentation_vod__c</code> objects for the user
	*/
    public PageReference updateVisibility() {
    	if(selectedCLMPrezisBeforeChange!=selectedCLMPrezis){
	    	System.Savepoint svp = Database.setSavepoint();
    		try{
	 	        updateCLMVisibility(selectedCLMPrezis);
	 	        if(HANDLE_KEY_MESSAGE_DOWNLOADS){
	 	        	handleKeyMessageDownloads();
	 	        }
//	 	        markCLMKeyMessagesForDownload();
	 	        recordTransactions();
	 	        doSystemResets();
		        message = CLMVisibilityManagerUtil.CLM_PREZI_SUCCESS_MSG;
    		}catch (Exception e){
    			ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.INFO,CLMVisibilityManagerUtil.CLM_PREZI_EXCEPTION_INTRO_MSG)) ;
    			ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR,e.getStackTraceString(), e.getStackTraceString())) ;
				Database.rollback(svp);
				HAS_ERROR = true;
    		}
    	}
    	else{
	        message = CLMVisibilityManagerUtil.CLM_PREZI_NOCHANGE_MSG;
    	}
        return null;       
    }
    
    private void handleKeyMessageDownloads(){
    	//get whats visible to Available to User just on Product basis
    	List<CLM_Presentation_vod__c> defaultAvailable = [SELECT Name, Id FROM Clm_Presentation_vod__c
    													where Product_vod__c in: CLMVisibilityManagerUtil.getUserMySetupProductIDs(UserInfo.getUserId())] ;
    	//compare this to list of CLM Presentations he actually has access to
    	List<SelectOption> userAvailable =  (List<SelectOption>) new UserSpecificOps().getUserVisiblePrezis(true);
    	Set<ID> defaultIDs = new Set<ID> ();
    	Set<ID> visibleIDs = new Set<ID> ();
    	
    	for(Clm_Presentation_vod__c aPrezi: defaultAvailable){
    		defaultIDs.add(aPrezi.Id);
    	}
    	for(SelectOption anOption: userAvailable){
    		visibleIDs.add(anOption.getValue());
    	}
    	if(defaultIDs!=null && visibleIDs!=null){
    		defaultIDs.removeAll(visibleIDs);
    	}
     	List<CLM_Presentation_vod__c> prezisToNOTDownload = [SELECT Id, 
    															(SELECT Id,Key_Message_vod__c FROM Clm_Presentation_Slide_vod__r), 
    															(SELECT Id,Key_Message_vod__c FROM Clm_Presentation_Slide_2_vod__r) 
    														FROM Clm_Presentation_vod__c
    														where Id in: defaultIDs];
    	
    	//Add a reference to Key Messages that are associated to Non-visible CLM Presentations into Invisible_CLM_Key_Message__c
    	Set<Invisible_CLM_Key_Message__c> invisibleKMObjSet = new Set<Invisible_CLM_Key_Message__c> ();
    	for(CLM_Presentation_vod__c aPrezi: prezisToNOTDownload){
    		for (Clm_Presentation_Slide_vod__c aSlide: aPrezi.Clm_Presentation_Slide_vod__r){
    			invisibleKMObjSet.add(new Invisible_CLM_Key_Message__c (
    								OwnerId = UserInfo.getUserId(), 
    								Key_Message__c = aSlide.Key_Message_vod__c, 
    								External_Id__c = UserInfo.getUserId() + '__' +aSlide.Key_Message_vod__c ));
    		}
    		for (Clm_Presentation_Slide_vod__c aSlide: aPrezi.Clm_Presentation_Slide_2_vod__r){
    			invisibleKMObjSet.add(new Invisible_CLM_Key_Message__c (
    								OwnerId = UserInfo.getUserId(), 
    								Key_Message__c = aSlide.Key_Message_vod__c, 
    								External_Id__c = UserInfo.getUserId() + '__' +aSlide.Key_Message_vod__c ));
    		}
    	}
    	//first clean out all Invisible KMs owned by this user
    	List<Invisible_CLM_Key_Message__c> invKMObjsToDelete = [select Id from Invisible_CLM_Key_Message__c where OwnerId = :UserInfo.getUserId()];
    	
    	if(invKMObjsToDelete!=null && invKMObjsToDelete.size() > 0){
    		delete invKMObjsToDelete;
    	}
    	
	   	//Now Insert to this table - a VMOC will typically use a NOT IN (Select Key_Message__c from Invisible_CLM_Key_Message__c) to ensure
    	//we stop the download of Key Messages to iRep that will not render due to inaccessible/invisible CLM Presentations
    	//VMOC on Key Messages (Global or Profile spec) - Where Id Not In (Select Key_Message_vod__c from Invisible_CLM_Key_Message__c where OwnerId = @@VOD_SF_USER_ID@@)
    	
    	if(invisibleKMObjSet!=null && invisibleKMObjSet.size() > 0){
    		insert new List<Invisible_CLM_Key_Message__c>(invisibleKMObjSet);
    	}
    }
    
    private void recordTransactions(){
    	if(transactionList!=null && transactionList.size() > 0){
    		insert transactionList;
    	}
    }
    private void doSystemResets(){
        originallyAvailablePrezis = new List<SelectOption> ();
        originallyAvailablePrezis.addAll(selectedCLMPrezis);
        selectedCLMPrezisBeforeChange = new List<SelectOption> ();
        selectedCLMPrezisBeforeChange.addAll(selectedCLMPrezis);
        newlyVisibleCLMIDs.clear();
    	newlyInvisibleCLMIDs.clear();
    	CLEAR_CACHE = true;
    	transactionList.clear();
  //  	clearVeevaCache();
    }
    
    /*
    * @methodDescription - Retrieves all available/non-accessible <code>Clm_Presentation_vod__c</code>
    * and returns the list in the form list of <code>SelectOption</code>
    */
    private List<SelectOption> getALLAvailableCLMPrezis(Boolean defaultOnly){
    	//Retrieve ALL CLM Presentations that are not already available to the user
    	List<Clm_Presentation_vod__c> defaultAvailablePrezis = [SELECT Name, Id FROM Clm_Presentation_vod__c
    													where Id not in: userAvailablePreziList
    													and Product_vod__c in: CLMVisibilityManagerUtil.getUserMySetupProductIDs(UserInfo.getUserId())] ;
    	System.debug('defaultAvailablePrezis = ' + defaultAvailablePrezis);
    	List<Clm_Presentation_vod__c> finallyAvailablePrezis = null;
    	if(defaultOnly){
    		return CLMVisibilityManagerUtil.convertToSelectOptions(defaultAvailablePrezis);
    	}
    	if(defaultAvailablePrezis!=null && defaultAvailablePrezis.size() > 0){
    		//prune this list based on CLM Visibility Configuration Objects (CVCs)
    		finallyAvailablePrezis = getFilteredAvailablePresentations(defaultAvailablePrezis);
    	}
     	return CLMVisibilityManagerUtil.convertToSelectOptions(finallyAvailablePrezis);
    }
    
    

    /*
    * @methodDescription - Filters down the CLM Prezi list based on CVCs for the logged in User
    */    
    private List<Clm_Presentation_vod__c> getFilteredAvailablePresentations(List<Clm_Presentation_vod__c> defaultPrezis){
    	//get the CVCs first - No CVC, no play
    	//get the Entity values - Users profile, profile id, user id & associated public groups
    	String userID = UserInfo.getUserId();
    	String profileID = UserInfo.getProfileId();
    	Set<String> userAssociatedGroups = new Set<String> ();
    	List<Clm_Presentation_vod__c> finalAvailablePrezis = new List<Clm_Presentation_vod__c> ();
    	for(GroupMember aGrp: [SELECT GroupId, Group.Name, Id, SystemModstamp, UserOrGroupId FROM GroupMember
									where UserOrGroupId =: userID]){
			userAssociatedGroups.add(aGrp.GroupId);							
		}
    	
    	//create a set of External Ids for Entity values
    	Set<String> cvcExternalIdSet = new Set<String> ();
    	cvcExternalIdSet.add(userID);
    	cvcExternalIdSet.add(profileID);
    	cvcExternalIdSet.addAll(userAssociatedGroups);
    	Set<String> availableClmPreziNames = new Set<String> ();
    	List<CLM_Visibility_Configuration__c> cvcList = [SELECT Entity_ID__c, Entity_Name__c, Entity_Type__c, External_Id__c, Id, Name
    														, Available_CLM_Presentations_1__c, Available_CLM_Presentations_2__c
    														, Use_Custom_Criteria__c, Custom_Criteria__c, Exclusive_Criteria__c
    															FROM CLM_Visibility_Configuration__c 
    															WHERE External_Id__c in: cvcExternalIdSet];
    	
    	if(cvcList == null || cvcList.size() == 0) {
    		return defaultPrezis;//NO CVCs, available list will be default
    	}
    	
    	//get the CVCs based on External Ids
    	String whereClause = '' ;
    	Integer index = 0;
    	Boolean atleastOneCustomCriteria = false;
    	Boolean atleastOneNameCriteria = false;
	
    	for(CLM_Visibility_Configuration__c aCVC: cvcList){
    		if(aCVC.Use_Custom_Criteria__c){
    			if(!atleastOneCustomCriteria){
    				atleastOneCustomCriteria = true;
    			}
    			else{
    				whereClause +=   (aCVC.Exclusive_Criteria__c) ? ' AND ' : ' OR ';//if its already true, put an IR condition to join the two conditions
     			}
     		//	whereClause += ' ( ' + String.escapeSingleQuotes(aCVC.Custom_Criteria__c) + ' )';
     			whereClause += ' ( ' + aCVC.Custom_Criteria__c + ' )';
    		}
    		else{
				String allAvailableCLMPrezis = aCVC.Available_CLM_Presentations_1__c + aCVC.Available_CLM_Presentations_2__c;
				availableClmPreziNames.addAll(allAvailableCLMPrezis.split(';'));
				atleastOneNameCriteria = true;
    		}
    	}
    	if(atleastOneCustomCriteria){
    		String clmPreziRetrieveQuery = 'SELECT Name, Id FROM Clm_Presentation_vod__c where Id in ';
    		Set<ID> defaultCLMPreziIDs = new Set<ID> ();
    		for(Clm_Presentation_vod__c aPrezi: defaultPrezis){
    			defaultCLMPreziIDs.add(aPrezi.ID);
    		}
    		clmPreziRetrieveQuery += ' :defaultCLMPreziIDs' +  ' AND (' + whereClause;//use the default list with AND criteria because you definitely don't want to go beyond default
    		if(atleastOneNameCriteria){
    			//(Name in: +')' + ')'
    			clmPreziRetrieveQuery += 'OR ( Name in :availableClmPreziNames )';
    		}
    		clmPreziRetrieveQuery += ')';
    		System.debug('Heres my ugly long DYnamic SOQL statement==> '  + clmPreziRetrieveQuery);
    		finalAvailablePrezis = (List<Clm_Presentation_vod__c>) Database.query(clmPreziRetrieveQuery);
    	}
    	else{
	    	//Filter out the CLM Presentations based on CVCs
	    	for(Clm_Presentation_vod__c aDefaultPrezi: defaultPrezis){
	    		if(availableClmPreziNames.contains(aDefaultPrezi.Name)){
	    			finalAvailablePrezis.add(aDefaultPrezi);
	    		}
	    	}
    	}
    	return finalAvailablePrezis;
    }
    /*
    * @methodDescription - Updates visibility to <code>Clm_Presentation_vod__c</code> for the end user
    */    
    private void updateCLMVisibility(List<SelectOption> selectedPrezis){
    	Set<ID> invisibleCopy = new Set<ID>();
		if(originallyAvailablePrezis!=null && originallyAvailablePrezis.size() > 0){
	    	removeExistingPreziVisbility(originallyAvailablePrezis);
	    	for(SelectOption aOption: originallyAvailablePrezis){
	    		newlyInvisibleCLMIDs.add(aOption.getValue());
	    	}
	    	if(newlyInvisibleCLMIDs!=null && newlyInvisibleCLMIDs.size() > 0){
	    		invisibleCopy.addAll(newlyInvisibleCLMIDs);	    		
	    	}
		}
		if(selectedPrezis!=null && selectedPrezis.size() > 0){
	    	addNewPreziVisibility(selectedPrezis);
	    	for(SelectOption aOption: selectedPrezis){
	    		newlyVisibleCLMIDs.add(aOption.getValue());
	    	}
		}
		if(newlyInvisibleCLMIDs!=null && newlyVisibleCLMIDs!=null){
			if(newlyVisibleCLMIDs.size() > 0){
				newlyInvisibleCLMIDs.removeAll(newlyVisibleCLMIDs);//now invisible only has what needs decrement
			}
			if(invisibleCopy.size() > 0){
				newlyVisibleCLMIDs.removeAll(invisibleCopy);//now visible only has what needs increment
			}
		}
    }

    /*
    * @methodDescription - Removes visibility to <code>Clm_Presentation_vod__c</code> for the end user
    */    

	private void removeExistingPreziVisbility(List<SelectOption> originalPrezis){
		Set<ID> preziIDSet = new Set<ID>();
		for(SelectOption aOption: originalPrezis){
			preziIDSet.add(aOption.getValue());
		}
		if(preziIDSet!=null && preziIDSet.size() > 0){
			List<Clm_Presentation_vod__Share> clmPreziShares = [Select Id , ParentId, UserOrGroupId
																  from Clm_Presentation_vod__Share
																  where ParentId in: preziIDSet
																  and UserOrGroupId = :UserInfo.getUserId()];
			if(clmPreziShares!=null && clmPreziShares.size() > 0){
				delete clmPreziShares;
			}
		}
	}
	
    /*
    * @methodDescription - Adds visibility to <code>Clm_Presentation_vod__c</code> for the end user
    */    
	private void addNewPreziVisibility(List<SelectOption> selectedPrezis){
    	List<Clm_Presentation_vod__Share> clmPreziShares = new List<Clm_Presentation_vod__Share>();
    	for(SelectOption aOption: selectedPrezis){
    		ID clmPreziID = aOption.getValue();
    		clmPreziShares.add(new Clm_Presentation_vod__Share(ParentId = clmPreziID, 
    															UserOrGroupId = UserInfo.getUserId(),
    															AccessLevel = CLMVisibilityManagerUtil.CLM_PREZI_DEFAULT_ACCESSLEVEL,
    															RowCause = Schema.Clm_Presentation_vod__Share.RowCause.VCVM_Manual_User_Selection__c));
    	}
	   	unchangedPrezisSet = new Set<ID> ();//reset this set
    	if(clmPreziShares!=null && clmPreziShares.size() > 0){
    		insert clmPreziShares;
    	}
	}

    /*
    * @classDescription - Inner class that respects sharing
    */    
	
    private with sharing Class UserSpecificOps {
	
	    private List<Object> getUserVisiblePrezis (Boolean returnSelectOptions){
	    	if(returnSelectOptions){
		    	return CLMVisibilityManagerUtil.convertToSelectOptions((List<Clm_Presentation_vod__c>)Database.query(CLMVisibilityManagerUtil.CLM_PREZI_USER_SPECIFIC_RETRIEVE_SOQL));
	    	}
	    	else{
	    		return Database.query(CLMVisibilityManagerUtil.CLM_PREZI_USER_SPECIFIC_RETRIEVE_SOQL);
	    	}
	    }
    }
    
    /*
    private  void markCLMKeyMessagesForDownload(){
    	Set<ID> idsToInclude = new Set<ID>();
    	idsToInclude.addAll(newlyInvisibleCLMIDs);
    	idsToInclude.addAll(newlyVisibleCLMIDs);
    	List<CLM_Presentation_vod__c> clmPrezisWorkedOn = [SELECT Id, 
    															(SELECT Id,Key_Message_vod__c, Key_Message_vod__r.CLM_Rep_Visibility_Count__c FROM Clm_Presentation_Slide_vod__r), 
    															(SELECT Id,Key_Message_vod__c, Key_Message_vod__r.CLM_Rep_Visibility_Count__c FROM Clm_Presentation_Slide_2_vod__r) 
    														FROM Clm_Presentation_vod__c
    														where Id in: idsToInclude];
    	Set<Key_Message_vod__c> keyMessagesToUpdate = new Set<Key_Message_vod__c>();
    	for(CLM_Presentation_vod__c aPrezi: clmPrezisWorkedOn){
    		List<Key_Message_vod__c> tmpList = null;
    		if(newlyVisibleCLMIDs.contains(aPrezi.Id)){ //if it contains in visible, no need to check in invisible
    			tmpList = enableContentDownload(aPrezi);
    		}
    		else{
    			tmpList = disableContentDownload(aPrezi);    			
    		}
    		if(tmpList!=null) {
    				keyMessagesToUpdate.addAll(tmpList);
    		}
    	}
    	if(keyMessagesToUpdate!=null && keyMessagesToUpdate.size() > 0 ){
    		update new List<Key_Message_vod__c>(keyMessagesToUpdate);//single DML to enable or disable Key Message flag	
    	}
    } 
    
    private List<Key_Message_vod__c> disableContentDownload(Clm_Presentation_vod__c aCLMPrezi){
    	transactionList.add(new CLM_Visibility_Manager_Transaction__c(User__c = UserInfo.getUserId(),
    																	Operation__c = 'Remove Visibility',
    																	CLM_Presentation__c = aCLMPrezi.Id));
    	return setKeyMessageDownloadFlag(aCLMPrezi, false);
     }
    
    private List<Key_Message_vod__c> enableContentDownload(Clm_Presentation_vod__c aCLMPrezi){
    	transactionList.add(new CLM_Visibility_Manager_Transaction__c(User__c = UserInfo.getUserId(),
    																	Operation__c = 'Add Visibility',
    																	CLM_Presentation__c = aCLMPrezi.Id));
    	return setKeyMessageDownloadFlag(aCLMPrezi, true);
    }
    
    private List<Key_Message_vod__c> setKeyMessageDownloadFlag(Clm_Presentation_vod__c aCLMPrezi, Boolean doIncrement){
    	List<Key_Message_vod__c> keyMsgs = new List<Key_Message_vod__c> ();
    	Integer counter = 0;
	   	List<Invisible_CLM_Key_Message__c> invisibleKMs = new List<Invisible_CLM_Key_Message__c> ();
     	
    	for(Clm_Presentation_Slide_vod__c aSlide: aCLMPrezi.Clm_Presentation_Slide_vod__r){
    		if(aSlide.Key_Message_vod__r.CLM_Rep_Visibility_Count__c==null){
    			counter = (doIncrement) ? 1 : 0;
    		}
    		else if(doIncrement){
    				counter = (Integer) aSlide.Key_Message_vod__r.CLM_Rep_Visibility_Count__c + 1; 
    		}
    		else if(!doIncrement && aSlide.Key_Message_vod__r.CLM_Rep_Visibility_Count__c!=0 ){
    			counter = (Integer) aSlide.Key_Message_vod__r.CLM_Rep_Visibility_Count__c - 1;    			
    		}
    		else {
    			continue;//nothing to update if the value is already zero and needs to be further decremented
    			//this may be the case if no visibility exists and user tries to add first time
    		}
    		keyMsgs.add(new Key_Message_vod__c(Id = aSlide.Key_Message_vod__c, CLM_Rep_Visibility_Count__c = counter));
    	}
     	return keyMsgs;
    }
    
    public void clearVeevaCache(){
    	message = 'Clearing Veeva cache..';
    	CLEAR_CACHE = false;
	   	HttpRequest req = new HttpRequest();
	    req.setEndpoint('/apex/ClearVeevaCacheVFPage');
	    req.setMethod('GET');
	    Http ht = new Http();
     	HTTPResponse res = ht.send(req);
     	System.debug('HTTP Response::::::!!!!' + res.getBody());   
    }
    public void enablePanelRendering(){
    	RENDER_PANEL = true;
    	message = 'Panel rendering enabled..' + RENDER_PANEL;
    	
    }
    */
    
}