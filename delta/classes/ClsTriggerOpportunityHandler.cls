/**
*  @Name: ClsTriggerOpportunityHandler
*  @return - void
*  @Description - This class helps to control the Opportunity Trigger logic
*  @Author : Rajesh Kaliyaperumal (Accenture)
*  Opportuniyt Handler : Set LPU and LPG* Opportuniyt Handler : Set LPU and LPG
*   Release R4
*  @author  MohanRaj Kasinathan (Accenture)
*  @created  2015-09-08
* @version 1.0
*/
public with sharing class ClsTriggerOpportunityHandler extends ClsTriggerVirtual {
    
    public Static Set<Id> processedOpptyIdSet = new Set<Id>();
    private Id profileId = UserInfo.getProfileId();
    //private String profileName = [SELECT Id, Name FROM Profile WHERE Id = :profileId LIMIT 1].Name;
    private String profileName = ProfileDAO.getProfileName(profileId);//Added by Lalitha -To avoid too many soql queries    
    private final static String EMPTY_STRING = '';
    private final static String STR_SYSTEM = 'System';
        
    /**
    * @see IntHelper.beforeTrigger
    */
    public override void beforeTrigger(ClsWrappers.TriggerContext trgCtx) {    
     Boolean stopOpportunityTrigger = false;
        if(trgCtx.isUpdate){
            for (sobject so : trgCtx.newList) {
                Opportunity newOppty = (Opportunity)so;
                Opportunity oldOppty = (Opportunity) trgCtx.oldMap.get(so.Id);
                if(newOppty.Active_Recurring_Business__c!=oldOppty.Active_Recurring_Business__c){
                    stopOpportunityTrigger = true;
                    break;
                }
            } 
        }
        if(!stopOpportunityTrigger){   
        //WA-931; WA-933
        if(trgCtx.isUpdate || trgCtx.isInsert) {
            populateAlterSubOpp(trgCtx);
        }
        
        //SFDC0399 Begin part 1/2
        PartnersUtils.transferPartnersToNewAccountCustomersBeforeUpdate(trgCtx);
        //SFDC0399 End part 1/2
        setOpportunityRecordtypeBefore(trgCtx);
        populateABBLocation(trgCtx);
        //Req 2280 - Updating Account End User with Account Customer if Channel Class is 'DEU' and Account End User is empty
        updateAccountEndUser(trgCtx);
        
        //ALM2812
        updateEndUserProjectSiteCountry(trgCtx);
        
        //Req 2500 - Preventing Account Customer LSO reference data and Account End User LSO reference data population from any account except the Account Customer and the Account End User
        checkAccountCustandAccountEULSOPopulation(trgCtx);
        //Req 2168 - Local reference data auto population on opportunity
        setLSORefDatafromAccount(trgCtx);    
        //Req 2504 - Preventing opportunity with open quotations from closure
        preventOpptyClosure(trgCtx);    
        
        //Req 2510 - Updating the main opportunity
        updateMainOpportunity(trgCtx);
        //Update Customer Preference
        updateCustomerPreference(trgCtx);
        //Update Owner Bu Field Values in Opportunity -- Created by Hari Charan (Modified by Indhu - Sts PR2.0)
        updateOpportunityBUFields(trgCtx);
        try
        {
            setLBUandLPG(trgCtx);
        }
        catch(DMLException e){  string err = e.getmessage(); } 
        
        updateServiceCategory(trgCtx);
        //R5 ServIS integration
        sendCloseOppRequestToServIS(trgCtx);
        //R8 Communtity User Opportunity CBP,SPP auto population based on Stage.
        partnerOpportunityFieldAutoPopulations(trgCtx);
        partnerAccountValidation(trgCtx);
        if(trgCtx.isUpdate){
            partnerasOpportunityTeamMember(trgCtx);
        }
        
        //Sts PR2.0 - Opportunity Management - Indhu
        if(trgCtx.isInsert || trgCtx.isUpdate){
            updateAccEndUserFromEUP(trgCtx);
            
            //Method called only for Internal Users in Before Trigger
            if(!profileName.equalsIgnoreCase(System.Label.SYS_ABBExtChannelPartnerCommunityUser) && 
                !profileName.equalsIgnoreCase(System.Label.SYS_ABB_Ext_Agent_Community_User) &&
                !profileName.equalsIgnoreCase(System.Label.SYS_ABB_Ext_Rep_Community_User)) {
                    probabilityRangeCheck(trgCtx);
            }
			//added by hari in R2.0 Hyper care for defect ID:5605
            if(profileName.equalsIgnoreCase(System.Label.SYS_ABBExtChannelPartnerCommunityUser) || 
                profileName.equalsIgnoreCase(System.Label.SYS_ABB_Ext_Agent_Community_User) ||
                profileName.equalsIgnoreCase(System.Label.SYS_ABB_Ext_Rep_Community_User)) {
                    altOppPrepopforOppUnderCase(trgCtx);
            }
        }
                if(trgCtx.isUpdate || trgCtx.isInsert){
        commitAndTargetUpdate(trgCtx);
        }
    }    
    }    
    /**    
    * @see IntHelper.afterTrigger
    */
    public override void afterTrigger(ClsWrappers.TriggerContext trgCtx) {          
Boolean stopOpportunityTrigger = false;
        if(trgCtx.isUpdate){
            for (sobject so : trgCtx.newList) {
                Opportunity newOppty = (Opportunity)so;
                Opportunity oldOppty = (Opportunity) trgCtx.oldMap.get(so.Id);
                if(newOppty.Active_Recurring_Business__c!=oldOppty.Active_Recurring_Business__c){
                    stopOpportunityTrigger = true;
                    break;
                }
            } 
        }        
        if(!stopOpportunityTrigger){            
        //Added by Indhu - Sts PR2.0 (Req no: 5682; User Story: 1328 and 1329)
        if(trgCtx.isInsert || trgCtx.isDelete) {
            updateDateOfRelatedRecordInOpp(trgCtx);
        } 

        //Method called only for External Users in After Trigger
        if ((trgCtx.isInsert || trgCtx.isUpdate) &&  
            (profileName.equalsIgnoreCase(System.Label.SYS_ABBExtChannelPartnerCommunityUser) || 
             profileName.equalsIgnoreCase(System.Label.SYS_ABB_Ext_Agent_Community_User) || 
             profileName.equalsIgnoreCase(System.Label.SYS_ABB_Ext_Rep_Community_User) )){ 
                probabilityRangeCheckForPortalUsers(trgCtx);
        }       
       
    if (trgCtx.isInsert && 
            (profileName.equalsIgnoreCase(System.Label.SYS_ABBExtChannelPartnerCommunityUser) || 
             profileName.equalsIgnoreCase(System.Label.SYS_ABB_Ext_Agent_Community_User) || 
             profileName.equalsIgnoreCase(System.Label.SYS_ABB_Ext_Rep_Community_User) )){ 
             /*SYS_ABBExtChannelPartnerCommunityUser-->ABB Ext Channel Partner Community User 
             SYS_ABB_Ext_Agent_Community_User -->ABB Ext Agent Community User
             SYS_ABB_Ext_Rep_Community_User --> ABB Ext Rep Community User */
        chatterPostForPartnerCreatedOpportunity(trgCtx);
     }
     //Added by Lalitha Rel2.0 ,WA 955 - To update the Lead when Opportunity is created from Lead ( Applicable only for portal users- ABB Ext Channel Partner Community User,   ABB Ext Rep Community User) 
      if((trgCtx.isInsert)  && 
            (profileName.equalsIgnoreCase(System.Label.SYS_ABBExtChannelPartnerCommunityUser) ||              
             profileName.equalsIgnoreCase(System.Label.SYS_ABB_Ext_Rep_Community_User) )){  
             updateOpportunityCreatedInLead(trgCtx);
             }
      
     if (trgCtx.isInsert && 
            !(profileName.equalsIgnoreCase(System.Label.SYS_ABBExtChannelPartnerCommunityUser) || 
             profileName.equalsIgnoreCase(System.Label.SYS_ABB_Ext_Agent_Community_User) || 
             profileName.equalsIgnoreCase(System.Label.SYS_ABB_Ext_Rep_Community_User) )){ 
             /*SYS_ABBExtChannelPartnerCommunityUser-->ABB Ext Channel Partner Community User 
             SYS_ABB_Ext_Agent_Community_User -->ABB Ext Agent Community User
             SYS_ABB_Ext_Rep_Community_User --> ABB Ext Rep Community User */
         addPartnersToOpportunityShare(trgCtx);
     }
        setContactAsPrimaryContactRole(trgCtx);
        setOpportunityRecordtypeAfter(trgCtx);
        createCCPQuoteSync(trgCtx);
        updateStatusToRB(trgCtx); //Update RB status whenever Opportunity been cancelled
        Savepoint sp;
        try
        {
            setContactAsPrimaryContactRole(trgCtx);
            
            //Req 2281 - Making the Competitor's Winning company field blank in case the Opportunity Winner selected is not a part of Competitor
            syncWinnerManualUpdate(trgCtx);
            
            //Req 2281 - Update Estimated Wnner's Price when Opportunity value is changed
            updateWinnerPrice(trgCtx);
            
            //SFDC0399 Begin part 2/2           
            PartnersUtils.transferPartnersToNewAccountCustomersAfterUpdate(trgCtx);            
            //SFDC0399 Endpart 2/2
            
            //Intiate copy to Combined Pipeline from Opportunity
            intiaiteCombinedPipelineUtility(trgCtx);
            sp = Database.setSavepoint();
            //Moved to end avoid insufficient access issue
            opportunityCreation(trgCtx);
            
        }
        catch(Exception e){  
            if(sp!= null){
                Database.rollback(sp);
            }
            else{
                string err = e.getmessage();
            }
        }
    }
    }

    /**   
    * @Author: Indhu Ramalingam
    * @name: updateDateOfRelatedRecordInOpp
    * @CreateDate: March 2018
    * @release: Sts PR2.0 Opportunity Management (Req no: 5682; User Story: 1328 and 1329) 
    * @Description: To reset the 'Neglected' counter in Opportunity record
    **/
    @TestVisible
    private static void updateDateOfRelatedRecordInOpp(ClsWrappers.TriggerContext trgCtx) {
        List<Opportunity> sObjectList = (trgCtx.isDelete) ? (List<Opportunity>) trgCtx.oldList : (List<Opportunity>)trgCtx.newList;            
        STS_OpportunityCommonHelper.captureActionOfRelatedList(sObjectList, 'Alternative_Opportunity_To__c', 'Opportunity');    //Pass API name of 'Opportunity' relationship field
        STS_OpportunityCommonHelper.captureActionOfRelatedList(sObjectList, 'Sub_Opportunity_To__c', 'Opportunity'); 
    }   
    
    /**
     * Method for populating Alternative Opp with Alternative Opp info - WA-931; WA-933
     * Case when alternative/sub opportunity information is set, hence alternative/sub opportunity must be populated or vice versa
    **/
    @TestVisible
    private void populateAlterSubOpp(ClsWrappers.TriggerContext trgCtx){
        //WA-931 linking between Alternative opportunity and Opportunity Information

        List<Map<String, String>> listAltSubOpp = new List<Map<String, String>>();
        Set<String> alterSubOppInfoIds = new Set<String>();
        Set<String> alterSubOppIds = new Set<String>();

        for(SObject oppObj : trgCtx.newList){
            Opportunity op = (Opportunity) oppObj;

            listAltSubOpp.add(
                    new Map<String, String>{
                        'Alternative_Opportunity_To__c' => op.Alternative_Opportunity_To__c,
                        'Alternative_Opportunity_Information_To__c' => op.Alternative_Opportunity_Information_To__c,
                        'Sub_Opportunity_To__c' => op.Sub_Opportunity_To__c,
                        'Sub_Opportunity_Information_To__c' => op.Sub_Opportunity_Information_To__c
                    }
            );
        }

        for(Map<String, String> el : listAltSubOpp){
            for(String key : el.keySet()){
                if(el.get(key) != null) {
                    if (key == 'Alternative_Opportunity_To__c' || key == 'Sub_Opportunity_To__c') {
                        alterSubOppIds.add(el.get(key));
                    } else {
                        alterSubOppInfoIds.add(el.get(key));
                    }
                }
            }
        }

        Map<Id, Opportunity_Information__c> oppInfoQueryList = new Map<Id, Opportunity_Information__c>([
                SELECT Id, Opportunity_Name_m__c
                FROM Opportunity_Information__c
                WHERE Id IN :alterSubOppInfoIds
                OR Opportunity_Name_m__c IN :alterSubOppIds
                LIMIT 50000
        ]);

        for(SObject oppObj : trgCtx.newList){
            Opportunity op = (Opportunity) oppObj;

            if(trgCtx.isUpdate){
                Opportunity oldOpp = (Opportunity) trgCtx.oldMap.get(op.Id);
                Opportunity newOpp = (Opportunity) trgCtx.newMap.get(op.Id);

                if(oldOpp.Alternative_Opportunity_To__c != newOpp.Alternative_Opportunity_To__c){
                    newOpp.Alternative_Opportunity_Information_To__c = null;
                } else if(oldOpp.Alternative_Opportunity_Information_To__c != newOpp.Alternative_Opportunity_Information_To__c){
                    newOpp.Alternative_Opportunity_To__c = null;
                }

                if(oldOpp.Sub_Opportunity_To__c != newOpp.Sub_Opportunity_To__c){
                    newOpp.Sub_Opportunity_Information_To__c = null;
                }else if(oldOpp.Sub_Opportunity_Information_To__c != newOpp.Sub_Opportunity_Information_To__c){
                    newOpp.Sub_Opportunity_To__c = null;
                }
            }

            if(op.Alternative_Opportunity_Information_To__c != null){
                op.Alternative_Opportunity_To__c = oppInfoQueryList.get(op.Alternative_Opportunity_Information_To__c).Opportunity_Name_m__c;
            }
            if(op.Sub_Opportunity_Information_To__c != null){
                op.Sub_Opportunity_To__c = oppInfoQueryList.get(op.Sub_Opportunity_Information_To__c).Opportunity_Name_m__c;
            }
            if(op.Alternative_Opportunity_To__c != null){
                for(Opportunity_Information__c value : oppInfoQueryList.values()){
                    if(value.Opportunity_Name_m__c == op.Alternative_Opportunity_To__c){
                        op.Alternative_Opportunity_Information_To__c = value.Id;
                    }
                }
            }
            if(op.Sub_Opportunity_To__c != null){
                for(Opportunity_Information__c value : oppInfoQueryList.values()){
                    if(value.Opportunity_Name_m__c == op.Sub_Opportunity_To__c){
                        op.Sub_Opportunity_Information_To__c = value.Id;
                    }
                }
            }
        }
    }
    
    /**
    *This method is used to sync status Opportunity to Recurring Business.
    @author  Rajesh Kaliypaerumal
    **/   
    @TestVisible 
    private void updateStatusToRB(ClsWrappers.TriggerContext trgCtx) 
    {
        if(trgCtx.isUpdate){            
            RBupdateOpportunityHelper.rbStatusUpdates(trgCtx.newList, trgCtx.oldMap);
            RBupdateOpportunityHelper.rbOwnerUpdate(trgCtx.newList, trgCtx.oldMap); // added for owner update
        } 
    }
    /**
    *This trigger is used to CCP Quotation Sync.
    @author  Rajesh Kaliypaerumal
    **/   
    @TestVisible 
    private void createCCPQuoteSync(ClsWrappers.TriggerContext trgCtx) 
    {
        if(trgCtx.isUpdate && ClsTriggerFactory.isSkipQuoteTrigger){
            CCP_QuotationSyncHelper.opportunityToQuotationSync(trgCtx.newList, trgCtx.oldMap);
        } 
    }
    
    /**
    This method used to populate the ABB Location on opportunity based on Logged in user BALID
    */
    public void populateABBLocation(ClsWrappers.TriggerContext trgCtx) {
        
        if (trgCtx.isInsert && trgCtx.isBefore) {
            
            User[] us = [ SELECT Id, ABB_Location_ID__c, ABB_Location_BAL_ID__c FROM User WHERE Id = :UserInfo.getUSerId()];
            
            for (Opportunity so : (List<Opportunity>) trgCtx.newList) {
               if (so.ABB_Location__c == NULL && us[0].ABB_Location_ID__c != NULL && us[0].ABB_Location_ID__c != '' && us[0].ABB_Location_BAL_ID__c != NULL && us[0].ABB_Location_BAL_ID__c != '') {
                    so.ABB_Location__c = us[0].ABB_Location_ID__c;
               }
            }
        }    
    }
   
    /**
     *This trigger is used to send request to ServIS.
     @author  Rajesh Kaliyaperumal
     @created 2016-02-22
    */
   @TestVisible 
    private void sendCloseOppRequestToServIS(ClsWrappers.TriggerContext trgCtx) {    
        if (trgCtx.isUpdate && trgCtx.isBefore) {
            Set<ID> setOppids = new Set<ID>();
            for (sobject so : trgCtx.newList) {
                Opportunity oppy = (Opportunity)so; 
                System.debug('ServIS Init Closure'+oppy.stageName + ' '+oppy.ServIS_Initiated__c + ' ' +oppy.ServIS_Iterator_check__c);              
                if(oppy.stageName.contains(System.label.Closed) && oppy.External_Originated_System__c  == 'ServIS'  && oppy.ServIS_Iterator_check__c){  // changes as per Jesus - ServIS: Jinal Bhatt                
                        System.debug('ServIS Identified Closure');
                        setoppids.add(oppy.id);
                        oppy.ServIS_Iterator_check__c= false;
                    }
                }            
            if(setoppids.size()>0){
                System.debug('ServIS Method Closure');
                if(System.isFuture()) {
                    return;
                }
                requesttoServIS(setoppids);
            }   
            /*if(setOppids.size()>0 && setOppids.size()<100){
                for(ID oppid : setOppids){              
                    
        }
                List<OpportunityLineItem> lstopplineitem = [Select ServIS_Opp_Id__c from OpportunityLineItem where opportunityid in: setOppids and ServIS_Opp_Id__c != null];
                if(lstopplineitem.size()>0 && lstopplineitem.size()<100){
                    for(OpportunityLineItem oppli : lstopplineitem){
                        if(oppli.ServIS_Opp_Id__c != null){
                            requesttoServIS(String.valueof(oppli.ServIS_Opp_Id__c), oppli.id);
                        }                       
                    }
                }
            }*/
        } 
    } 
/**
 *void method void requesttoServIS.
*/        
    @Future(callout=true)
    Public static void requesttoServIS(Set<Id> setoppids)
    {
        List<Opportunity> lstupdOpportunity = new List<Opportunity>();
        for(Id oppid : setoppids){
            System.debug('ServIS Future Closure');
            HttpRequest req = new HttpRequest();
            req.setMethod(System.label.INTEG_SYS_SERVIS_Response_GET);
            String autorithationServIS = System.label.SYS_ServIS_Autorithation;
            req.setHeader('Authorization', autorithationServIS );
            //String reqbody = 'https://www1008.abb.com/stage/servisws/sfdc/Opportunity.svc/close/13Q1492017?email='+ 'mariusz.stala@pl.abb.com';
            String endpointS = System.label.INTEG_SYS_SERVIS_endPoint;
            String reqbody = endpointS + String.valueof(oppid) +'?email='+ UserInfo.getUserEmail();
            req.setEndpoint(reqbody); 
            Http http = new Http();
            try{
                HTTPResponse res = http.send(req);
                System.debug('Servis Feedback Object' + String.valueof(res));
                System.debug('Servis Feedback Body' + String.valueof(res.getBody()));
                //lstupdOpportunity.add(new Opportunity(id = oppid, ServIS_Response_Feedback__c = String.valueof(res.getBody())));
            }catch(Exception e){System.debug('ServIS error'+ e.getMessage());}
        }   
        /**try{     
        Database.update(lstupdOpportunity, false);
        }catch(Exception e){String err=e.getMessage();}*/
    }
    /**
    *  @Name: setOpportunityRecordtypeBefore
    *  @return - void
    *  @Description - Method to set default channel class from account,
    *  decide record type based on Product Group condition
    *  Method updated to set defalut channel class level1 and level2 from account
    */ 
    @TestVisible 
    private void setOpportunityRecordtypeBefore(ClsWrappers.TriggerContext trgCtx) {        
                    
        List<Opportunity> lstopp = new List<Opportunity>();
        Set<Id> accids = new Set<Id>();
        Set<Id> oppIds = new Set<Id>();
        Map<Id, List<OpportunityLineItem>> mapOppLineItems = new Map<Id, List<OpportunityLineItem>>();
        Set<String> productGroups = new Set<String>();
        //Map<String,CurrencyType> conversion_rates = new Map<String,CurrencyType>();
        Map<String, Product_Group__c> mapProductGroups = new Map<String, Product_Group__c>();
        String oPP_INITIAL_RECORD_TYPE_ID = RecordTypeManager.getRecordTypeId('Opportunity.Initial');
        String oPP_REGULAR_RECORD_TYPE_ID = RecordTypeManager.getRecordTypeId('Opportunity.Regular');
        String oPP_FASTTRACK_RECORD_TYPE_ID = RecordTypeManager.getRecordTypeId('Opportunity.Fast_Track');

        if(trgCtx.isBefore && trgCtx.isInsert)
        {               
            Map<id,Account> mapaccount = new Map<Id,Account>([Select id, Channel_Class_Level1__c, Channel_Class_Level2__c from Account where Id IN: accids LIMIT 50000]);
            Map<id,Product_Group__c> mapProductGroup = new Map<Id,Product_Group__c>(ClsTriggerOpportunityHandler.getProductGroups(trgCtx,'id in productGroupIds'));
            for (sobject so : trgCtx.newList) {
                Opportunity oppy = (Opportunity)so;                 
                if (mapaccount.containskey(oppy.AccountId) && mapaccount.get(oppy.AccountId).Channel_Class_Level1__c!= null && oppy.Channel_Class_Level1__c == null) {                    
                    oppy.Channel_Class_Level1__c = mapaccount.get(oppy.AccountId).Channel_Class_Level1__c;
                    oppy.Channel_Class_Level2__c = mapaccount.get(oppy.AccountId).Channel_Class_Level2__c;
                }
                /*if (mapaccount.containskey(oppy.AccountId) && mapaccount.get(oppy.AccountId).Channel_Class_Level2__c!= null && oppy.Channel_Class_Level2__c == null) {
                    //oppy.Channel_Class_Level2__c = mapaccount.get(oppy.AccountId).Channel_Class_Level2__c;
                }*/
                
               /* if (mapaccount.get(oppy.AccountId).Industry__c != null) { 
                    // oppy.Industry_Usage__c = mapaccount.get(oppy.AccountId).Industry__c;
                }*/
                /*if(oppy.Product_Group__c == null){
                    oppy.Recordtypeid = oPP_INITIAL_RECORD_TYPE_ID;
                }*/
                //set Record type change as per business logic, Product group's default equals "Regular" or opportunity's value exceeds Product Group's threshold
                if(mapProductGroup.containsKey(oppy.Product_Group__c) && oppy.Product_Group__c != null){
                    /*if(mapProductGroup.get(oppy.Product_Group__c).Opportunity_Default_Type__c.equals(System.label.Opportunity_RecordType_Regular) ||  
                    (oppy.Opportunity_Value__c != null && mapProductGroup.get(oppy.Product_Group__c).Opportunity_Threshold__c != null && 
                    (oppy.Opportunity_Value__c/conversion_rates.get(oppy.CurrencyIsoCode).ConversionRate) > (mapProductGroup.get(oppy.Product_Group__c).Opportunity_Threshold__c/conversion_rates.get(mapProductGroup.get(oppy.Product_Group__c).CurrencyIsoCode).ConversionRate))){
                        oppy.Recordtypeid = oPP_REGULAR_RECORD_TYPE_ID;
                    }else{
                        oppy.Recordtypeid = oPP_FASTTRACK_RECORD_TYPE_ID;
                    }*/
                    oppy.isPGManualUpdate__c = true;
                }
            }
        }        
        
        //set Record type change as per business logic, 
        //Product group's default equals "Regular" or opportunity's value exceeds Product Group's threshold
        if(trgCtx.isBefore && trgCtx.isUpdate && ClsTriggerFactory.isSkipOpportunityRecursiveTrigger == true){
            Set<String> productGroupNames = ClsTriggerOpportunityHandler.getProductGroupNames(trgCtx);
            Map<String,Product_Group__c> mapProductGroupNames = new Map<String,Product_Group__c>();
            for(Product_Group__c objPG : ClsTriggerOpportunityHandler.getProductGroups(trgCtx,'name in productGroupNames')){
                mapProductGroupNames.put(objPG.Name,objPG);
            }
            for (sobject so : trgCtx.newList) {
                Opportunity oppy = (Opportunity)so;               
                if(((Opportunity)trgCtx.oldMap.get(oppy.Id)).Product_Group__c != oppy.Product_Group__c && oppy.Product_Group__c != null){
                    oppy.isPGManualUpdate__c = true;
                }
                /*if(((Opportunity)trgCtx.oldMap.get(oppy.Id)).Product_Group__c != oppy.Product_Group__c && oppy.Product_Group__c == null && oppy.Is_Product_Available__c == false){                   
                    oppy.Recordtypeid = oPP_INITIAL_RECORD_TYPE_ID;
                }else if(((Opportunity)trgCtx.oldMap.get(oppy.Id)).Product_Group__c != oppy.Product_Group__c && oppy.Product_Group__c == null && oppy.isPGManualUpdate__c == true && oppy.Product_Primary_PG__c == null){
                    oppy.Recordtypeid = oPP_INITIAL_RECORD_TYPE_ID;
                }*/
                if(oppy.isPGManualUpdate__c == false && oppy.Product_Primary_PG__c == null)
                    oppy.Product_Group__c = null;
                if(oppy.Product_Group__c == null && oppy.Product_Primary_PG__c != null && mapProductGroupNames.containskey(oppy.Product_Primary_PG__c)){                    
                    oppy.Product_Group__c = mapProductGroupNames.get(oppy.Product_Primary_PG__c).id;
                    oppy.isPGManualUpdate__c = false;
                }               
               /* if(oppy.Product_Group__c == null && oppy.Product_Primary_PG__c == null){
                    oppy.Recordtypeid = oPP_INITIAL_RECORD_TYPE_ID;
                }
                
                System.debug('Logging111:'+ oppy.Recordtypeid);
                System.debug('Logging222:'+ oppy.Product_Group__c);
                System.debug('Logging333:'+ oppy.Product_Primary_PG__c);*/
            }
            //ClsTriggerFactory.isSkipOpportunityRecursiveTrigger = false;
        }        
    }    
    /**
    *  @Name: setOpportunityRecordtypeAfter
    *  @return - void
    *  @Description - Method to set record type based on Product Group condition
    */ 
    @TestVisible 
    private void setOpportunityRecordtypeAfter(ClsWrappers.TriggerContext trgCtx) {     
        //if(trgCtx.isAfter && trgCtx.isUpdate && ClsTriggerFactory.isSkipOpportunityRecursiveTrigger == true){
        if(trgCtx.isAfter && trgCtx.isUpdate && ClsTriggerFactory.isSkipOpportunityRecursiveTrigger){
            Set<Id> productGroupids = new Set<Id>();
            Set<String> productGroupNames = new Set<String>();          
            List<Opportunity> lstupdOpportunity = new List<Opportunity>();
            //List<Opportunity> lstupdOpportunity1 = new List<Opportunity>();
            //Map<String,CurrencyType> conversion_rates = new Map<String,CurrencyType>();
            Set<Id> oppIds = new Set<Id>();
            Set<Id> prodIds = new Set<Id>();
            Map<ID, String> mapProducts = new Map<ID, String>();
            Map<Id, List<OpportunityLineItem>> mapOppLineItems = new Map<Id, List<OpportunityLineItem>>();
            String oPP_INITIAL_RECORD_TYPE_ID = RecordTypeManager.getRecordTypeId('Opportunity.Initial');
            String oPP_REGULAR_RECORD_TYPE_ID = RecordTypeManager.getRecordTypeId('Opportunity.Regular');
            String oPP_FASTTRACK_RECORD_TYPE_ID = RecordTypeManager.getRecordTypeId('Opportunity.Fast_Track');
            Map<String,Product_Group__c> mapProductGroupNames = new Map<String,Product_Group__c>();
            for (sobject so : trgCtx.newList) {
                Opportunity oppy = (Opportunity)so;
                //if(oppy.Is_Cancelled__c != true){
                //if(oppy.Is_Cancelled__c != true){
                    if(oppy.Product_Group__c != null){
                        productGroupids.add(oppy.Product_Group__c);                   
                    }
                    oppIds.add(oppy.id);
                    productGroupNames.add(oppy.Product_Primary_PG__c);
                //}


            }
            ClsTriggerOpportunityProductHandler objOppProductHandler = new ClsTriggerOpportunityProductHandler();
            mapOppLineItems = objOppProductHandler.buildOpportunitylineitem(oppIds);
            
            for(ID oppId : mapOppLineItems.Keyset())  
            { 
                for(OpportunityLineItem opplineRec : mapOppLineItems.get(oppId)){                   
                    prodIds.add(opplineRec.Product2id);
                }
            }
            for(Product2 prod : [Select id,Product_Group__c from Product2 where id in:prodIds LIMIT 50000]){
                mapProducts.put(prod.id,String.valueof(prod.Product_Group__c));
            } 
            
            /*for(CurrencyType curr : [SELECT ISOCode, ConversionRate FROM CurrencyType WHERE IsActive=TRUE LIMIT 50000]){
                conversion_rates.put(curr.ISOCode,curr);
            }*/
            Map<id,Product_Group__c> mapProductGroup = new Map<Id,Product_Group__c>(ClsTriggerOpportunityHandler.getProductGroups(trgCtx,'name in productGroupNames'));
            for(Product_Group__c objPG : mapProductGroup.values()){
                mapProductGroupNames.put(objPG.Name,objPG);
            }
            for (sobject so : trgCtx.newList) {
                Opportunity oppy = (Opportunity)so;
                //if(oppy.Is_Cancelled__c != true){
                //if(oppy.Is_Cancelled__c != true){
                    Boolean groupCheck = false;
                    if(mapOppLineItems.containsKey(oppy.id)){
                        for(OpportunityLineItem oppline : mapOppLineItems.get(oppy.id)){
                            if(mapProducts.get(oppline.Product2id) != null){
                                groupCheck = true;
                            }
                        }
                    }

                    //if(oppy.isPGManualUpdate__c == true && ((Opportunity)trgCtx.oldMap.get(oppy.Id)).Recordtypeid != oppy.Recordtypeid && oppy.Product_Group__c != null){                    
                   /* if(oppy.isPGManualUpdate__c == true && oppy.Product_Group__c != null){                    
                        if(mapProductGroup.get(oppy.Product_Group__c).Opportunity_Default_Type__c.equals(System.label.Opportunity_RecordType_Regular) ||  
                        (oppy.Opportunity_Value__c != null && mapProductGroup.get(oppy.Product_Group__c).Opportunity_Threshold__c != null && 
                        (oppy.Opportunity_Value__c/conversion_rates.get(oppy.CurrencyIsoCode).ConversionRate) > (mapProductGroup.get(oppy.Product_Group__c).Opportunity_Threshold__c/conversion_rates.get(mapProductGroup.get(oppy.Product_Group__c).CurrencyIsoCode).ConversionRate)) && oppy.Stagename == 'Opportunity Pursuit'){                        
                            lstupdOpportunity.add(new Opportunity(id = oppy.id, Recordtypeid = oPP_REGULAR_RECORD_TYPE_ID));
                        }//Added for 4.1 changes
                        else if(oppy.Stagename == 'Opportunity Pursuit'){
                            lstupdOpportunity.add(new Opportunity(id = oppy.id, Recordtypeid = oPP_FASTTRACK_RECORD_TYPE_ID));
                        }
                        //Removed for 4.1 changes
                        /*else if(((Opportunity)trgCtx.oldMap.get(oppy.Id)).Recordtypeid <> oPP_REGULAR_RECORD_TYPE_ID && oppy.Recordtypeid <> oPP_REGULAR_RECORD_TYPE_ID){
                            lstupdOpportunity.add(new Opportunity(id = oppy.id, Recordtypeid = oPP_FASTTRACK_RECORD_TYPE_ID));                                                             

                        }

                    }*/

                    System.debug('Outside');
                    //if(oppy.isPGManualUpdate__c == false && (((Opportunity)trgCtx.oldMap.get(oppy.Id)).Opportunity_Value__c != oppy.Opportunity_Value__c)|| ((Opportunity)trgCtx.oldMap.get(oppy.Id)).Recordtypeid != oppy.Recordtypeid){
                    //if(oppy.isPGManualUpdate__c == false){
                    if(oppy.isPGManualUpdate__c == false){
                    System.debug('Inside');
                        ID productid = null;
                        if(mapProductGroupNames.containskey(oppy.Product_Primary_PG__c)){
                            productid = mapProductGroupNames.get(oppy.Product_Primary_PG__c).id;
                        }
                        //>>>>>>>>>>>>>>>>>>>
                        Decimal oppValue = 0;
                        if(oppy.Opportunity_Value__c != null){
                            oppValue = oppy.Opportunity_Value__c;
                        }    
                        //>>>>>>>>>>>>>
                       System.debug('Logging777:'+productid);
                       lstupdOpportunity.add(new Opportunity(id = oppy.id, Product_Group__c = productid));
                       /* if(oppy.Product_Group__c == null && groupCheck == false && (oppy.Product_Primary_PG__c == null || productid == null)){
                            lstupdOpportunity.add(new Opportunity(id = oppy.id, Recordtypeid = oPP_INITIAL_RECORD_TYPE_ID));
                        }else if(oppy.Is_Product_Available__c == true && (oppy.If_any_PG_Regular__c == true || oppValue/conversion_rates.get(oppy.CurrencyIsoCode).ConversionRate > oppy.Min_Product_Group_Threshold__c) && oppy.Stagename == 'Opportunity Pursuit'){
                            lstupdOpportunity.add(new Opportunity(id = oppy.id, Product_Group__c = productid, Recordtypeid = oPP_REGULAR_RECORD_TYPE_ID));
                        }else if(oppy.Is_Product_Available__c == true && (oppy.Recordtypeid == oPP_FASTTRACK_RECORD_TYPE_ID || ((Opportunity)trgCtx.oldMap.get(oppy.Id)).Recordtypeid != oPP_REGULAR_RECORD_TYPE_ID) && oppy.Stagename == 'Opportunity Pursuit'){   //Check here
                            lstupdOpportunity.add(new Opportunity(id = oppy.id, Product_Group__c = productid, Recordtypeid = oPP_FASTTRACK_RECORD_TYPE_ID));

                        }else{
                            lstupdOpportunity.add(new Opportunity(id = oppy.id, Product_Group__c = productid));
                        }*/
                    }

                    //Removed for 4.1 release
                    /*if(oppy.isRegularButtonUpdate__c == true){
                        lstupdOpportunity1.add(new Opportunity(id = oppy.id, isRegularButtonUpdate__c = false, Recordtypeid = oPP_REGULAR_RECORD_TYPE_ID));
                    }*/
                    
                //}

            }           
            ClsTriggerFactory.isSkipOpportunityRecursiveTrigger = false;
            if(lstupdOpportunity.size()>0){
                Database.update(lstupdOpportunity, false);
            }
            /*if(lstupdOpportunity1.size()>0){
                Database.update(lstupdOpportunity1, false);

            }*/
        }           
    }
    /**
     *  This trigger is used to Set Contact to Primary with a Role.
     @author  Jinbo Shan
     @created 2015-03-26
     @version 1.0
     @since   30.0 (Force.com ApiVersion)
     *
     @changelog
     * 2015-03-26 Jinbo Shan <jinbo.shan@itbconsult.com>
     * - Created
    */
    @TestVisible 
    private void setContactAsPrimaryContactRole(ClsWrappers.TriggerContext trgCtx) {
    
        if (trgCtx.isBefore){return;}
        
        if (trgCtx.isInsert) {
            list<OpportunityContactRole> list_ocrs = new list<OpportunityContactRole>();
            for (sobject so : trgCtx.newList) {
                Opportunity oppy = (Opportunity)so;
                if (oppy.Primary_Contact__c != null) {
                    OpportunityContactRole ocr = new OpportunityContactRole();
                    ocr.IsPrimary = true;
                    ocr.OpportunityId = oppy.Id;
                    ocr.ContactId = oppy.Primary_Contact__c;
                    ocr.Role = Label.System_CL00083;
                    list_ocrs.add(ocr);
                }
            }
            if(list_ocrs.size() > 0) {
                Database.Insert(list_ocrs);
            }
        } 
    }      
   
    /*  Description of the purpose of the method. 
    *  @name setLSORefDatafromAccount
    *  @Description - Req -2168. Auto populates the Local Reference Data from associated Accounts while creating or updating an opportunity.
    *  @return - void
    *  @created by - Shankar Anand
    */
    private void setLSORefDatafromAccount(ClsWrappers.TriggerContext trgCtx) {   
        Set<Id> accountCustIds = new Set<Id>();
        Set<Id> accountEndUserIds = new Set<Id>();
        Set<Id> opptyOwnerIds = new Set<Id>(); 
        Set<id> opptyIds = new Set<id>();
        Set<Id> primPartnerAccIds = new Set<Id>(); 
        String userLSO;
        String userLSO1;
        String accLSO;
        String primPartnerLSO;      
        //Map<Id,Opportunity> oldOpptyMap = new map<Id,Opportunity>();
        Map<Id,Account> accountCustMap = new map<Id,Account>();
        Map<Id,Account> accountEndUserMap = new map<Id,Account>();
        Map<Id,User> userMap = new map<Id,User>();
        //Map<Id,OpportunityPartner> primPartners= new map<Id,OpportunityPartner>();        
        Map<Id,Account> primPartnerAccnts = new map<Id,Account>();
        Set<ID> allAccountids = new Set<ID>();
        List<Account> lstAccounts = new List<Account>();
        Set<Id> opptyPrimPartLRDList = new Set<Id>();
        Boolean autoPopulate = true;
        
        if(trgCtx!=null && trgCtx.isBefore && 
           (trgCtx.isInsert || trgCtx.isUpdate) &&
           ClsTriggerFactory.isSkipRecursiveLSOTrigger)
           //ClsTriggerFactory.isSkipRecursiveLSOTrigger == true)//(trgCtx.isUpdate && ClsTriggerFactory.isSkipRecursiveLSOTrigger == true)))
        { 
            for(sobject so : trgCtx.newList) {
                Opportunity oppy = (Opportunity)so;
                if(trgCtx.isInsert || (trgCtx.isUpdate && ((Opportunity)trgCtx.oldMap.get(oppy.id)).accountId != oppy.accountId || 
                   ((Opportunity)trgCtx.oldMap.get(oppy.id)).ownerId != oppy.ownerId))
                {
                accountCustIds.add(oppy.accountId);
                }
                if(trgCtx.isInsert || (trgCtx.isUpdate && ((Opportunity)trgCtx.oldMap.get(oppy.id)).Account_End_User__c != oppy.Account_End_User__c || 
                   ((Opportunity)trgCtx.oldMap.get(oppy.id)).ownerId != oppy.ownerId))
                {
                accountEndUserIds.add(oppy.Account_End_User__c);
                }
                if(trgCtx.isInsert || (trgCtx.isUpdate && ((Opportunity)trgCtx.oldMap.get(oppy.id)).accountId != oppy.accountId || 
                   ((Opportunity)trgCtx.oldMap.get(oppy.id)).Account_End_User__c != oppy.Account_End_User__c || 
                   ((Opportunity)trgCtx.oldMap.get(oppy.id)).ownerId != oppy.ownerId))
                {
                opptyOwnerIds.add(oppy.ownerId);
                }
                opptyIds.add(oppy.id);
                if(trgCtx.isUpdate && ((Opportunity)trgCtx.oldMap.get(oppy.id)).Primary_Partner_LSO_Reference_Data__c != oppy.Primary_Partner_LSO_Reference_Data__c)
                {
                opptyPrimPartLRDList.add(oppy.Primary_Partner_LSO_Reference_Data__c);
                }
            }
            
            allAccountids.addall(accountCustIds);
            allAccountids.addall(accountEndUserIds);
            if(allAccountids.size()>0){
                lstAccounts = [Select Id, Name, (Select Id, name,LBU__c,LSO__c,LSO_ERP_Mapping_Value__c from LSO_Reference_Datas__r LIMIT 50000) 
                               FROM Account WHERE id in:allAccountids LIMIT 50000];
            }
            for(Account acc:lstAccounts){
                if(accountCustIds.contains(acc.id)){
                    accountCustMap.put(acc.id, acc);
                }
                if(accountEndUserIds.contains(acc.id)){
                    accountEndUserMap.put(acc.id,acc);
                }
            }
            /*if(accountCustIds.size()>0){
                accountCustMap = new map<Id,Account>([Select Id, Name, (Select Id, name,LBU__c,LSO__c,LSO_ERP_Mapping_Value__c from LSO_Reference_Datas__r) from Account where id in:accountCustIds LIMIT 50000]);
            }
            if(accountEndUserIds.size()>0){
                accountEndUserMap = new map<Id,Account>([Select Id, Name, (Select Id, name,LBU__c,LSO__c,LSO_ERP_Mapping_Value__c from LSO_Reference_Datas__r) from Account where id in:accountEndUserIds LIMIT 50000]);
            }*/
            
            if(opptyOwnerIds.size()>0){
            userMap = new map<Id,User>([Select Id, Name,Default_BU__c,Default_LSO__c,Default_Country_ISO_Code__c 
                                        FROM User WHERE Id in:opptyOwnerIds LIMIT 50000]);                     
            }               
        }
                   
        if(trgCtx!=null && trgCtx.isBefore && trgCtx.isInsert){ 
            for(sobject so : trgCtx.newList) {
                Opportunity oppy = (Opportunity)so;  
                Account acu = accountCustMap.get(oppy.accountId);
                Account eua = new Account();
                if(accountEndUserMap.containskey(oppy.Account_End_User__c)){
                    eua = accountEndUserMap.get(oppy.Account_End_User__c);
                }
                User usr = userMap.get(oppy.ownerid);
                if(usr!= null && usr.Default_BU__c != null){
                    userLSO = usr.Default_LSO__c + usr.Default_BU__c;
                }

                else if(usr!=null){
                    userLSO1 = usr.Default_LSO__c;
                }
                                           
                if(acu!=null){
                    for(ERP_Reference_Data__c lrd:acu.LSO_Reference_Datas__r){
                        accLSO = String.valueof(lrd.LSO__c)+String.valueof(lrd.LBU__c);
                        if(usr.Default_BU__c!=null && lrd.LBU__c!= null && userLSO!=null && userLSO.equalsIgnoreCase(accLSO)){
                            oppy.Account_Customer_LSO_Reference_Data__c = lrd.id;
                        }
                        else if(usr.Default_BU__c==null &&  lrd.LBU__c == null && 
                                userLSO1!=null && userLSO1.equalsIgnoreCase(String.valueof(lrd.LSO__c))){
                            oppy.Account_Customer_LSO_Reference_Data__c = lrd.id;
                        }
                       
                    }
                }
                
                if(eua!=null){
                    for(ERP_Reference_Data__c lrd:eua.LSO_Reference_Datas__r){
                        accLSO = String.valueof(lrd.LSO__c)+String.valueof(lrd.LBU__c);
                        if(usr.Default_BU__c!=null &&  lrd.LBU__c!= null && userLSO!=null && userLSO.equalsIgnoreCase(accLSO)){
                            oppy.End_User_LSO_Reference_Data__c = lrd.id;
                        }
                        else if(usr.Default_BU__c ==null &&  lrd.LBU__c == null && userLSO1!=null && userLSO1.equalsIgnoreCase(String.valueof(lrd.LSO__c))){    
                            oppy.End_User_LSO_Reference_Data__c = lrd.id;
                        }
                          
                    }
                }       
            }  
        } 

        //if(trgCtx!=null && trgCtx.isBefore && trgCtx.isUpdate && ClsTriggerFactory.isSkipRecursiveLSOTrigger == true)// && ClsTriggerFactory.isSkipRecursiveLSOTrigger == true)
        if(trgCtx!=null && trgCtx.isBefore && trgCtx.isUpdate && ClsTriggerFactory.isSkipRecursiveLSOTrigger )
        { 
            List<OpportunityPartner> primPartners = new List<OpportunityPartner>();
            Map<Id,ERP_Reference_Data__c> lrdMap = new Map<Id,ERP_Reference_Data__c>();
            Map<Id,OpportunityPartner> partnerMap = new Map<Id,OpportunityPartner>();     
            primPartners = [Select Id,role,isPrimary,OpportunityId,accountToId 
                            FROM OpportunityPartner WHERE isPrimary = true and OpportunityId in :opptyIds LIMIT 50000];
            

            for(OpportunityPartner prtnr : primPartners){
                        partnerMap.put(prtnr.OpportunityId,prtnr);
                }
                   
             for(sobject so : trgCtx.newList){
                Opportunity oppy1 = (Opportunity)so;
                OpportunityPartner opt = partnerMap.get(oppy1.id);
                if(opt!=null && oppy1.Primary_Partner_LSO_Reference_Data__r.account__c!=opt.accountToId){
                    primPartnerAccIds.add(opt.accountToId);
                }
                }    
                                 
            /*for(OpportunityPartner pp:primPartners){
                primPartnerAccIds.add(pp.accountToId);  
            }*/
            
            if(primPartnerAccIds.size()>0){
                primPartnerAccnts = new map<Id,Account>([Select Id, Name, (Select Id, name,LBU__c,LSO__c,LSO_ERP_Mapping_Value__c 
                                                         FROM LSO_Reference_Datas__r LIMIT 50000) FROM Account WHERE id in:primPartnerAccIds LIMIT 50000]);              
            }
            /*for(sobject so : trgCtx.oldList){
                Opportunity oppy = (Opportunity)so;
                oldOpptyMap.put(oppy.id,oppy);       
            }*/

        if(opptyPrimPartLRDList.size()>0){
        lrdMap = new Map<Id,ERP_Reference_Data__c>([Select Id, Name, Account__c 
                     from ERP_Reference_Data__c 
                     where Id in: opptyPrimPartLRDList LIMIT 50000]); 
        }                                                                          

            for(sobject so : trgCtx.newList) 
            {
                Opportunity oppy = (Opportunity)so;
                Account eua = new Account();
                if(accountEndUserMap.containskey(oppy.Account_End_User__c)){
                    eua = accountEndUserMap.get(oppy.Account_End_User__c);
                }    
                
                /*for(OpportunityPartner prtnr : primPartners){
                    if(prtnr.opportunityId == oppy.id){
                        partnerMap.put(oppy.Id,prtnr);
                    }
                }*/

                User usr = userMap.get(oppy.ownerid);
                if(usr!=null && usr.Default_BU__c!=null){
                    userLSO = usr.Default_LSO__c+usr.Default_BU__c;
                }

                else if(usr!=null){
                    userLSO1 = usr.Default_LSO__c;
                }
                
                
                
                if(((Opportunity)trgCtx.oldMap.get(oppy.id)).accountId != oppy.accountId || 
                   ((Opportunity)trgCtx.oldMap.get(oppy.id)).ownerId != oppy.ownerId){
                Account act = accountCustMap.get(oppy.accountId);    
                if(act!=null){  
                    List<ERP_Reference_Data__c> acLsoRefList = new List<ERP_Reference_Data__c>();
                    acLsoRefList.addall(act.LSO_Reference_Datas__r);                
                    if(acLsoRefList.size()>0){
                        for(ERP_Reference_Data__c lrd:act.LSO_Reference_Datas__r){
                            accLSO = String.valueof(lrd.LSO__c)+String.valueof(lrd.LBU__c);
                            if(usr!=null && usr.Default_BU__c!=null && lrd.LBU__c!= null && userLSO!=null && userLSO.equalsIgnoreCase(accLSO)){
                                oppy.Account_Customer_LSO_Reference_Data__c = lrd.id;

                                break;
                            }
                            else if(usr!=null && usr.Default_BU__c == null && lrd.LBU__c == null && 
                                    userLSO1!=null && userLSO1.equalsIgnoreCase(String.valueof(lrd.LSO__c))){
                                oppy.Account_Customer_LSO_Reference_Data__c = lrd.id;
                                break;
                            }
                            else{
                                oppy.Account_Customer_LSO_Reference_Data__c = null;
                            }
                        }
                    }
                    else{
                        oppy.Account_Customer_LSO_Reference_Data__c = null;
                    }               
                }

                }
                 
                 
                if(((Opportunity)trgCtx.oldMap.get(oppy.id)).Account_End_User__c != oppy.Account_End_User__c || 
                   ((Opportunity)trgCtx.oldMap.get(oppy.id)).ownerId != oppy.ownerId){    
                if(eua!=null){
                    List<ERP_Reference_Data__c> aeuLsoRefList = new List<ERP_Reference_Data__c>();
                    aeuLsoRefList.addall(eua.LSO_Reference_Datas__r);           
                    if(aeuLsoRefList.size()>0){
                        for(ERP_Reference_Data__c lrd:eua.LSO_Reference_Datas__r){
                            accLSO = String.valueof(lrd.LSO__c)+String.valueof(lrd.LBU__c);
                            if(usr!=null && usr.Default_BU__c!=null &&  lrd.LBU__c!= null && 
                               userLSO!=null && userLSO.equalsIgnoreCase(accLSO)){
                                oppy.End_User_LSO_Reference_Data__c = lrd.id;
                                break;
                            }
                            else if(usr!=null && usr.Default_BU__c==null &&  lrd.LBU__c == null 
                                    && userLSO1!=null && userLSO1.equalsIgnoreCase(String.valueof(lrd.LSO__c))){
                                oppy.End_User_LSO_Reference_Data__c = lrd.id;
                                break;
                            }
                            else{
                            oppy.End_User_LSO_Reference_Data__c  = null;
                            }
                        }
                    }
                    else{
                        oppy.End_User_LSO_Reference_Data__c  = null;
                    }
                }           

                }

                    
                    //R5-Req2500
                    OpportunityPartner opt = partnerMap.get(oppy.id);
                       if(opt == null && oppy.Primary_Partner_LSO_Reference_Data__c != null){              
                         oppy.addError(System.Label.Oppty_Primary_Partner_LSO_Error_Message);
                       } 
                       else if(opt!= null && opt.OpportunityId == oppy.Id 
                               && lrdMap.get(oppy.Primary_Partner_LSO_Reference_Data__c)!=null 
                               && lrdMap.get(oppy.Primary_Partner_LSO_Reference_Data__c).Account__c != opt.accountToId){
                                  oppy.addError(System.Label.Oppty_Primary_Partner_LSO_Error_Message);    
                       }
                       else if(opt!= null && opt.OpportunityId == oppy.Id && 
                               lrdMap.get(oppy.Primary_Partner_LSO_Reference_Data__c)!=null && 
                               lrdMap.get(oppy.Primary_Partner_LSO_Reference_Data__c).Account__c == opt.accountToId){
                        autoPopulate = false; 
                       } 
                     // END
              
        
               
                //if(partnerMap.containskey(oppy.id) && autoPopulate == true){
                if(partnerMap.containskey(oppy.id) && autoPopulate){
                    OpportunityPartner op = partnerMap.get(oppy.id);
                    List<ERP_Reference_Data__c> partnerLsoRefList = new List<ERP_Reference_Data__c>();
                    if(primPartnerAccnts!=null && op!=null && primPartnerAccnts.get(op.accountToId)!=null){
                       partnerLsoRefList.addall(primPartnerAccnts.get(op.accountToId).LSO_Reference_Datas__r);
                    }   
                    if(partnerLsoRefList.size()>0){  
                        for(ERP_Reference_Data__c lrd:primPartnerAccnts.get(op.accountToId).LSO_Reference_Datas__r){
                            primPartnerLSO = String.valueof(lrd.LSO__c)+String.valueof(lrd.LBU__c);
                            if(usr!=null && usr.Default_BU__c!=null &&  lrd.LBU__c!= null 
                               && userLSO!=null && userLSO.equalsIgnorecase(primPartnerLSO) 
                               &&  op.isPrimary){
                               //&&  op.isPrimary == true){
                                oppy.Primary_Partner_LSO_Reference_Data__c  = lrd.id;
                                break;
                            }
                            else if(usr!=null && usr.Default_BU__c ==null &&  lrd.LBU__c == null 
                                    && userLSO1!=null && userLSO1.equalsIgnorecase(String.valueof(lrd.LSO__c))  
                                     &&  op.isPrimary){
                                   // &&  op.isPrimary == true){
                                oppy.Primary_Partner_LSO_Reference_Data__c = lrd.id;
                                break;
                            }
                            else{
                                oppy.Primary_Partner_LSO_Reference_Data__c = null;
                            }
                        }
                    }
                    else{
                    oppy.Primary_Partner_LSO_Reference_Data__c = null;
                    }  
                }
            } 
            ClsTriggerFactory.isSkipRecursiveLSOTrigger = false;  
        }  
    }                
      

    /**   
    * Opportuniyt Handler : Set LPU and LPG Method
    * Release R4
    *  
    * @author  MohanRaj Kasinathan (Accenture)
    * @created  2015-09-08* @version 1.0
    *
    */    
    @TestVisible 
    private void setLBUandLPG(ClsWrappers.TriggerContext trgCtx) {
               
        if ((trgCtx.isBefore && trgCtx.isInsert) || (trgCtx.isBefore && trgCtx.isUpdate) ) {
            Set<String> setLBUCode = new Set<String>();
            Set<String> setLPGcode = new Set<String>();
            Set<Id> locIds = new Set<Id>();
            Map<Id,ABB_Location__c > abbLocMap = new Map<Id,ABB_Location__c >();
            Map<String, Id> lBUMap = new Map<String, Id>();
            Map<String, Id> lPGMap = new Map<String, Id>();
            for (sobject so : trgCtx.newList) {
                Opportunity oppy = (Opportunity)so;
                if ((trgCtx.isUpdate && ((Opportunity)trgCtx.oldMap.get(oppy.id)).ABB_Location__c!=oppy.ABB_Location__c 
                     && oppy.ABB_Location__c != null) 
                     || (trgCtx.isInsert && oppy.ABB_Location__c != null)) {                                  
                    locIds.add(oppy.ABB_Location__c);
                  }
            }
            if(locIds.size()>0){
            abbLocMap = new Map<Id,ABB_Location__c >([Select Id,Company__c,BU__c,Product_Group__c 
                                                      FROM ABB_Location__c WHERE Id in : locIds limit 50000]);
            }
            for(ABB_Location__c loc : abbLocMap .values()) {
            
            
            String strBU = '';                    
            if(loc.BU__c != null)
            {                   
            String[] strBUarr = loc.BU__c.split(Label.System_CL00081); 
            if(strBUarr.size() >0 ) {strBU = strBUarr[0].trim(); }                    
            }
            
            String strCompany = '';
            if(loc.Company__c != null)
            { strCompany = loc.Company__c;}                    
                                                   
            String strLBUCode = strCompany+Label.System_CL00081+strBU;  
             
            String strPG = '';
            if(loc.Product_Group__c != null)
            {
            String[] strPGarr = loc.Product_Group__c.split(Label.System_CL00081);
            if(strPGarr.size() >0 ) {strPG = strPGarr[0].trim(); }                     
            } 
                             
            String strLPGCode = strPG;  

            setLBUCode.add(strLBUCode);
            setLPGcode.add(strLPGCode);
            
            }
            
            if(setLBUCode.size()>0){                
            for (LBU_Code__c r : [Select Id, Name from LBU_Code__c where Name in : setLBUCode limit 50000]) {
            lBUMap.put(r.Name, r.Id);
            }
            }
            
            if(setLPGCode.size()>0){              
            for (Product_Group__c r : [Select Id, Name from Product_Group__c where Name in : setLPGCode limit 50000]) {
            lPGMap.put(r.Name, r.Id);
            }
            }

            for (sobject so : trgCtx.newList) {
                Opportunity oppy = (Opportunity)so;
                if (oppy.ABB_Location__c != null) {                                  
                    
                    String strBU = '';                    
                    if(abbLocMap.get(oppy.ABB_Location__c)!=null && abbLocMap.get(oppy.ABB_Location__c).BU__c != null)
                    {                   
                    String[] strBUarr = abbLocMap.get(oppy.ABB_Location__c).BU__c.split(Label.System_CL00081); 
                    if(strBUarr.size() >0 ) {strBU = strBUarr[0].trim(); }                    
                    }
                    
                    String strCompany = '';
                    if(abbLocMap.get(oppy.ABB_Location__c)!=null && abbLocMap.get(oppy.ABB_Location__c).Company__c != null)
                    { strCompany = abbLocMap.get(oppy.ABB_Location__c).Company__c;}                    
                                                           
                    String strLBUCode = strCompany+Label.System_CL00081+strBU;  
                     
                    String strPG = '';
                    if(abbLocMap.get(oppy.ABB_Location__c)!=null && abbLocMap.get(oppy.ABB_Location__c).Product_Group__c != null)
                    {
                    String[] strPGarr = abbLocMap.get(oppy.ABB_Location__c).Product_Group__c.split(Label.System_CL00081);
                    if(strPGarr.size() >0 ) {strPG = strPGarr[0].trim(); }                     
                    } 
                                     
                    String strLPGCode = strPG;  
                    
                    Id strLBUId = lBUMap.get(strLBUCode);   
                    Id strLPGId = lPGMap.get(strLPGCode); 
                    if(strLBUId!=null){                                                       
                    oppy.Local_Business_Unit__c = strLBUId;
                    }
                    if(strLPGId!=null){
                    oppy.Local_Product_Group__c = strLPGId;
                    }                    
                  }
            }



         } 
    }
    
    /*  Description of the purpose of the method. 
    *  @name opportunityCreation
    *  @Description - Provide the Status of Opportunity Capture Team Indicator while create a new Opportunity.
    *  @return Nothing - 
    */
    @TestVisible 
    private void opportunityCreation(ClsWrappers.TriggerContext trgCtx) {
        Set<Id> setEUPId = new Set<Id>();
        Map<Id,List<Opportunity>> mapEUPIdAndOpportunity = new Map<Id,List<Opportunity>>();
        List<End_User_Project__c> lstEndUsr = new List<End_User_Project__c>();
       
        if((Trigger.isInsert && Trigger.isAfter) || (Trigger.isUpdate && Trigger.isAfter))
        {
                        
             for(sobject objOpp : trgCtx.newList)
             {
                  Opportunity opp = (Opportunity)objOpp;
                  if(opp.End_User_Project__c != NULL)
                  {setEUPId.add(opp.End_User_Project__c);}
             }
             
            if (!setEUPId.isEmpty()) {
                for(Opportunity op : [SELECT Id,Capture_Team_Indicator_Status__c,End_User_Project__c
                FROM Opportunity  where End_User_Project__c in: setEUPId LIMIT 10000] )
                {
                    List<Opportunity> lstop = new List<Opportunity>();
                    lstop.add(op);

                    if (mapEUPIdAndOpportunity.containsKey(op.End_User_Project__c))
                    {
                        mapEUPIdAndOpportunity.get(op.End_User_Project__c).add(op);
                    }
                    else
                    {
                        mapEUPIdAndOpportunity.put(op.End_User_Project__c, lstop);
                    }

                }
            }
            
            for(String endusrid : setEUPId)
            {   
                String endUsrStatus = ''; 
                Boolean isFullRequired = False;
                Boolean isFullAvailable = False;
                Boolean isLiteRequired = False;
                Boolean isLiteAvailable = False;
                Boolean isNotRequired = False;       
                List<Opportunity> lstopty = new List<Opportunity>();
                if(mapEUPIdAndOpportunity.containsKey(endusrid)){
                    lstopty = mapEUPIdAndOpportunity.get(endusrid);
                }
                if(lstopty.size() >0){
                   for(Opportunity opp : lstopty)
                   {
                      if(null!=opp.Capture_Team_Indicator_Status__c&&opp.Capture_Team_Indicator_Status__c.equals(System.label.No_CT_Required))
                      { isNotRequired = True;}
                      if(null!=opp.Capture_Team_Indicator_Status__c&&opp.Capture_Team_Indicator_Status__c.equals(System.label.CT_Full_Available))
                      { isFullAvailable = True;}
                      if(null!=opp.Capture_Team_Indicator_Status__c&&opp.Capture_Team_Indicator_Status__c.equals(System.label.CT_Full_Required))
                      { isFullRequired = True;}
                      if(null!=opp.Capture_Team_Indicator_Status__c&&opp.Capture_Team_Indicator_Status__c.equals(System.label.CT_Lite_Available))
                      { isLiteAvailable = True;}
                      if(null!=opp.Capture_Team_Indicator_Status__c&&opp.Capture_Team_Indicator_Status__c.equals(System.label.CT_Lite_Required))
                      { isLiteRequired = True;}
                  
                   }
                }
                
                
                if(isFullAvailable)
                {
                    endUsrStatus = System.label.CT_Full_Available;
                }
                else if (isFullRequired)
                {
                    endUsrStatus = System.label.CT_Full_Required;
                }
                else if (isLiteAvailable)
                {
                    endUsrStatus = System.label.CT_Lite_Available;
                }
                else if (isLiteRequired)
                {
                    endUsrStatus = System.label.CT_Lite_Required;
                }
                else if(isNotRequired)
                {
                    endUsrStatus = System.label.No_CT_Required;
                }
                else
                {
                    endUsrStatus = System.label.No_CT_Required;
                }
                
                End_User_Project__c edUsrRec = new End_User_Project__c();
                edUsrRec.Id = endusrid;
                edUsrRec.Capture_Team_Status__c= endUsrStatus;                                
                lstEndUsr.add(edUsrRec);
            }
            
            if(lstEndUsr.size() > 0)
            {
                Database.update(lstEndUsr);
            }
        }
    } 
 /**   
    * This method prevents the user from closing an opportunity which has open quotes
    * Release R5
    *  
    * @author  Shankar Anand (Accenture)
    * @created  2015-16-12* @version 1.0
    *
    */    
    @TestVisible 
    private void preventOpptyClosure(ClsWrappers.TriggerContext trgCtx) 
    {
               
        if (trgCtx.isBefore && trgCtx.isUpdate) 
        {
            Set<Id> closedOpptyIds = new Set<Id>();
            Map<Id,Apttus_Proposal__Proposal__c> quoteMap = new Map<Id,Apttus_Proposal__Proposal__c>();
            for (sobject so : trgCtx.newList) 
            {
                Opportunity oppy = (Opportunity)so;
                if (oppy.StageName.equals(System.Label.Opportunity_Closed_Lost) || oppy.StageName.equals(System.Label.Opportunity_Closed_Won) || 
                    oppy.StageName.equals(System.Label.Opportunity_Closed_Cancelled) || oppy.StageName.equals(System.Label.Opportunity_ClosedLost_Without_ABB_Bid))
                {                                  
                    closedOpptyIds.add(oppy.Id);
                }
            }
            
            Id cqpId = RecordTypeManager.getRecordTypeId('Apttus_Proposal__Proposal__c.CQP'); //system_CL00106 -> CQP
            Id lpSpain = RecordTypeManager.getRecordTypeId('Apttus_Proposal__Proposal__c.LP'); // System_CL00107 -> LP
            List<Id> recordTypes = new List<Id>();
            recordTypes.add(cqpId);
            recordTypes.add(lpSpain);
            if(closedOpptyIds.size()>0){
                quoteMap = new Map<Id,Apttus_Proposal__Proposal__c>([Select Id, Name, Apttus_Proposal__Opportunity__c, RecordTypeid, Quotation_status__c,
                                                                APTS_Quotation_Category__c, isSync__c, IsMultiQuoteSync__c, Apttus_Proposal__Approval_Stage__c, APTS_Is_Alternative__c
                                                                FROM Apttus_Proposal__Proposal__c WHERE Apttus_Proposal__Opportunity__c in : closedOpptyIds and recordTypeid in :recordTypes AND APTS_Is_Placeholder_Quote__c = false limit 50000]);
            }
         

            for (sobject so : trgCtx.newList) 
            {
                Opportunity oppy = (Opportunity)so;
                if(((Opportunity)trgCtx.oldMap.get(oppy.Id)).StageName!=oppy.StageName && closedOpptyIds.contains(oppy.Id)){
                    for(Apttus_Proposal__Proposal__c quot: quoteMap.values()){
                        if (quot != null && quot.Apttus_Proposal__Approval_Stage__c != null && QuoteStatus_Sequence__c.getValues(quot.Apttus_Proposal__Approval_Stage__c) != null) {
                            Decimal seqNumber = QuoteStatus_Sequence__c.getValues(quot.Apttus_Proposal__Approval_Stage__c).Sequence_Number__c;
                            if (quot.Apttus_Proposal__Opportunity__c != null && quot.Apttus_Proposal__Opportunity__c.equals(oppy.Id) &&
                                    (quot.APTS_Quotation_Category__c == System.label.Open || (quot.RecordTypeid == cqpId && !quot.isSync__c && !quot.IsMultiQuoteSync__c && !quot.APTS_Is_Alternative__c && seqNumber < Decimal.valueof(System.Label.Quotation_Approved_Sequence_Number)))) {
                                oppy.addError(System.Label.Oppty_Error_Message);
                                System.debug('---' + quot);
                            }
                        }
                    }
                }
            }

         } 
    }

    /**   
    * This method updates the main opportunity on the alternative opportunities
    * Release R5
    *  
    * @author  Shankar Anand (Accenture)
    * @created  2015-16-12* @version 1.0
    *
    */    
     @TestVisible 
    private void updateMainOpportunity(ClsWrappers.TriggerContext trgCtx) {
        ClsTriggerAlternativeOpptyHandler.updateMainOpportunity(trgCtx);
       
    }
    
    
    
    /**   
    * This method prevents the user from populating the Account Customer LSO Reference Data field 
    * and the End User LSO Reference Data field from any account except from the Account Customer
    * and the Account End User
    * Release R5
    *  
    * @author  Shankar Anand (Accenture)
    * @created  2016-12-01* @version 1.0
    *
    */    
    @TestVisible 
    private void checkAccountCustandAccountEULSOPopulation(ClsWrappers.TriggerContext trgCtx) 
    {
    if (trgCtx.isBefore && trgCtx.isUpdate){

        Map<Id,ERP_Reference_Data__c> accCustlrdMap = new Map<Id,ERP_Reference_Data__c>();
        Map<Id,ERP_Reference_Data__c> accEUlrdMap = new Map<Id,ERP_Reference_Data__c>();
        Set<Id> opptyIds = new Set<Id>();
        Set<Id> opptyAccCustLRDList = new Set<Id>();
        Set<Id> opptyAccEULRDList = new Set<Id>();
        Set<ID> allLRDids = new Set<ID>();
        List<ERP_Reference_Data__c> lstLRDs = new List<ERP_Reference_Data__c>();
        String error ='';
        
        for(sobject so : trgCtx.newList) {
                Opportunity oppty = (Opportunity)so;
                opptyIds.add(oppty.id);
                opptyAccCustLRDList.add(oppty.Account_Customer_LSO_Reference_Data__c);
                opptyAccEULRDList.add(oppty.End_User_LSO_Reference_Data__c);      
            }
 
        allLRDids.addAll(opptyAccCustLRDList);
        allLRDids.addAll(opptyAccEULRDList); 
         
        
        if(allLRDids.size()>0){
           lstLRDs = [Select Id, Name, Account__c from ERP_Reference_Data__c where Id in: allLRDids LIMIT 50000];
          }
            
        for(ERP_Reference_Data__c lrd: lstLRDs){
           if(opptyAccCustLRDList.contains(lrd.id)){
              accCustlrdMap.put(lrd.id, lrd);
             }
           if(opptyAccEULRDList.contains(lrd.id)){
              accEUlrdMap.put(lrd.id, lrd);
             }
           }

        for(sobject so : trgCtx.newList){
            Opportunity oppty = (Opportunity)so;
           
            if(((Opportunity)trgCtx.oldMap.get(oppty.id)).Account_Customer_LSO_Reference_Data__c!= oppty.Account_Customer_LSO_Reference_Data__c 
                && accCustlrdMap.get(oppty.Account_Customer_LSO_Reference_Data__c)!=null 
                && accCustlrdMap.get(oppty.Account_Customer_LSO_Reference_Data__c).Account__c != oppty.accountId){
               oppty.addError(System.Label.Opportunity_Account_Customer_LSO_error_message);
              }    
            else if(((Opportunity)trgCtx.oldMap.get(oppty.id)).End_User_LSO_Reference_Data__c!= oppty.End_User_LSO_Reference_Data__c 
                     && accEUlrdMap.get(oppty.End_User_LSO_Reference_Data__c)!=null 
                     && accEUlrdMap.get(oppty.End_User_LSO_Reference_Data__c).Account__c != oppty.Account_End_User__c){
               oppty.addError(System.Label.Opportunity_Account_End_User_LSO_error_message);
              }
              
            /*if(accCustlrdMap.get(oppty.Account_Customer_LSO_Reference_Data__c)!=null && accCustlrdMap.get(oppty.Account_Customer_LSO_Reference_Data__c).Account__c != oppty.accountId && accEUlrdMap.get(oppty.End_User_LSO_Reference_Data__c)!=null && accEUlrdMap.get(oppty.End_User_LSO_Reference_Data__c).Account__c != oppty.Account_End_User__c){
               error = System.Label.Opportunity_Account_Customer_LSO_error_message + '<br/>' + System.Label.Opportunity_Account_End_User_LSO_error_message;
               oppty.addError(error,false);
              }  
             */         
          }  
      }
      } 
      
       
      /**   
    * This method updates the Account End User with Account Customer 
    * if Channel Class is DEU and Account End User is empty.
    * Release R5
    *  
    * @author  Shankar Anand (Accenture)
    * @created  2015-19-01* @version 1.0
    *
    */    
    @TestVisible 
    private void updateAccountEndUser(ClsWrappers.TriggerContext trgCtx) 
    {
        if (trgCtx.isBefore && (trgCtx.isInsert || trgCtx.isUpdate)) 	//"Update" Added by Indhu - STS PR2.0 Hypercare
        {
            for (sobject so : trgCtx.newList) 
            {
                Opportunity oppy = (Opportunity)so;
                if (null!=oppy.Channel_Class_Level1__c && oppy.Channel_Class_Level1__c.equals(System.label.DEU) && oppy.Account_End_User__c == null)
                {                                  
                    oppy.Account_End_User__c = oppy.AccountId;
                }
            }
        } 									  
    }
    
    /**   
    * This method updates the Opportunity with End User Project Site country gathered from End User Project
    * fix for the defect ALM2812
    *  
    */    
    
    
    private void updateEndUserProjectSiteCountry(ClsWrappers.TriggerContext trgCtx) 
    {
        if (trgCtx.isInsert || trgCtx.isUpdate) 
        {
            for (sobject so : trgCtx.newList) 
            {
                Opportunity oppty = (Opportunity)so;
                
                System.debug('*** End User Project Id:' + String.valueof(oppty.End_User_Project__c));
                
                if (oppty.End_User_Project__c != null)
                {                                  
                    
                    oppty.End_User_Project_Site_Country__c = oppty.End_User_Project_Site_Country_Calc__c;
                }

            }
            
    
        }      
    }
     
    /**   
    * This method updates the Estimated WInner's Price on Opportunity when the
    * Opportunity Value is updated and the Opportunity Winner is populated with a competitor
    * Release R5
    *  
    * @author  Shankar Anand (Accenture)
    * @created  2016-17-02* @version 1.0
    *
    */    
    @TestVisible 
    private void updateWinnerPrice(ClsWrappers.TriggerContext trgCtx) 
    {
    Set<Id> opptyIds = new Set<Id>();
    Map<Id,Opportunity> updOpptyIds = new Map<Id,Opportunity>();
    Map<Id,Competitor__c> compMap = new Map<Id,Competitor__c>();
    List<Opportunity> opptyList = new List<Opportunity>();
        if (trgCtx.isAfter && trgCtx.isUpdate) 
        {
            for (sobject so : trgCtx.newList) 
            {
                Opportunity oppy = (Opportunity)so;
                if ((((Opportunity)trgCtx.oldMap.get(oppy.id)).Opportunity_Value__c!=oppy.Opportunity_Value__c && oppy.Opportunity_Winner__c!=null))
                {                                 
                    opptyIds.add(oppy.Id);
                }

            }
        if(opptyIds.size()>0){ 
            compMap = new Map<Id,Competitor__c>([Select Id, Name, Competitor__c, Opportunity__c, Estimated_Sale_Price__c, Winning_Company__c 
                                                 FROM Competitor__c 
                                                 WHERE Opportunity__c in :opptyIds and Winning_Company__c = true LIMIT 50000]);   
        }
        
            for (sobject so : trgCtx.newList) 
            {
            Opportunity oppy = (Opportunity)so;
            Opportunity oppt = new Opportunity();
                if ((((Opportunity)trgCtx.oldMap.get(oppy.id)).Opportunity_Value__c!=oppy.Opportunity_Value__c && oppy.Opportunity_Winner__c!=null))
                {                 
                 for(Competitor__c cmp : compMap.values()){
                    if(cmp.Opportunity__c == oppy.Id && cmp.Competitor__c == oppy.Opportunity_Winner__c){                    
                        oppt = new Opportunity(id=oppy.Id,Winners_Price__c=cmp.Estimated_Sale_Price__c);
                    }
                 }
                 if(oppt.id == null){ 
                     oppt = new Opportunity(id=oppy.Id,Winners_Price__c=null);
                 }
                 updOpptyIds.put(oppt.id,oppt);
                }
            }
            if(updOpptyIds.values().size()>0 && !clsTriggerFactory.competitorUpdate){
                opptyList.addAll(updOpptyIds.values());
                Database.Update(opptyList);
            }
        }      
    }
    
    /**   
    * This method updates the Estimated WInner's Price on Opportunity when the
    * Opportunity Value is updated and the Opportunity Winner is populated with a competitor
    * Release R5
    *  
    * @author  Shankar Anand (Accenture)
    * @created  2016-17-02* @version 1.0
    *
    */    
    @TestVisible 
    private void syncWinnerManualUpdate(ClsWrappers.TriggerContext trgCtx) 
    {
    Set<Id> opptyIds = new Set<Id>();
    Map<Id,Opportunity> updOpptyMap = new Map<Id,Opportunity>();
    List<Opportunity> oppList = new List<Opportunity>();
    Map<Id,Competitor__c> updCompIds = new Map<Id,Competitor__c>();
    Map<Id,Competitor__c> compMap = new Map<Id,Competitor__c>();
    List<Competitor__c> comptList = new List<Competitor__c>();
        if (trgCtx.isAfter && trgCtx.isUpdate) 
        {
            for (sobject so : trgCtx.newList) 
            {
                Opportunity oppy = (Opportunity)so;
                if (((Opportunity)trgCtx.oldMap.get(oppy.id)).Opportunity_Winner__c!=oppy.Opportunity_Winner__c)
                {                                 
                    opptyIds.add(oppy.Id);
                }

            }
        
        if(opptyIds.size()>0){ 
            compMap = new Map<Id,Competitor__c>([Select Id, Name, Competitor__c, Opportunity__c, Estimated_Sale_Price__c, Winning_Company__c 
                                                 FROM Competitor__c 
                                                 WHERE Opportunity__c in :opptyIds LIMIT 50000]);   
        }
        
            for (sobject so : trgCtx.newList) 
            {
            Opportunity oppy = (Opportunity)so;
            Opportunity oppty = new Opportunity();
            Competitor__c compt = new Competitor__c();
                if (((Opportunity)trgCtx.oldMap.get(oppy.id)).Opportunity_Winner__c!=oppy.Opportunity_Winner__c)
                {                 
                 for(Competitor__c cmp : compMap.values()){
                    if(cmp.Opportunity__c == oppy.Id  && cmp.Competitor__c != oppy.Opportunity_Winner__c && cmp.Winning_Company__c){                    
                        compt = new Competitor__c(id=cmp.Id,Winning_Company__c = false);   
                    }
                    else if(cmp.Opportunity__c == oppy.Id  && cmp.Competitor__c == oppy.Opportunity_Winner__c && !cmp.Winning_Company__c){
                        oppty = new Opportunity(id=oppy.id,Winners_Price__c=cmp.Estimated_Sale_Price__c);
                        compt = new Competitor__c(id=cmp.Id,Winning_Company__c = true);
                    }
                  
                  if(compt.id != null){ 
                      updCompIds.put(compt.id,compt);
                  }
                 }
                 if(oppty.id != null){
                     updOpptyMap.put(oppty.id,oppty);
                 }
                 else if(null!= updCompIds.values() && updCompIds.values().size()>0 && null!= updOpptyMap.values() && updOpptyMap.values().size()==0  && ((Opportunity)trgCtx.oldMap.get(oppy.id)).Winners_Price__c == oppy.Winners_Price__c){
                     oppty = new Opportunity(id=oppy.id,Winners_Price__c=null);
                     updOpptyMap.put(oppty.id,oppty);
                 }
                }
            }
            
            if(null!=updCompIds.values() && updCompIds.values().size()>0 && !clsTriggerFactory.competitorUpdate){
                comptList.addAll(updCompIds.values());
                Database.Update(comptList);
            }
            
             if(null!=updOpptyMap.values() && updOpptyMap.values().size()>0 && !clsTriggerFactory.competitorUpdate){
                oppList.addAll(updOpptyMap.values());
                Database.Update(oppList);
            }
        }      
    }

    // ALM-5127 BEGIN
    // Trying to optimalize SOQL Queries
	private static List<Product_Group__c> productGroupList;
	private static List<Product_Group__c> getProductGroups(ClsWrappers.TriggerContext trgCtx, String criterium) {
		Set<Id> productGroupIds = ClsTriggerOpportunityHandler.getProductGroupIds(trgCtx);
		Set<String> productGroupNames = ClsTriggerOpportunityHandler.getProductGroupNames(trgCtx);
		List<Id> pgList = ClsTriggerOpportunityHandler.getPGList(trgCtx);
		if(ClsTriggerOpportunityHandler.productGroupList == null) {
            ClsTriggerOpportunityHandler.productGroupList =  [
                SELECT Id, Name, Business_Unit__c, CurrencyIsoCode, Division__c,
                    Opportunity_Default_Type__c, Opportunity_Threshold__c, Product_Group_Code__c
                FROM Product_Group__c
                WHERE
                (
                    Id IN: productGroupids
                    OR Name IN : ProductGroupNames
                    OR Id = : pgList
                )
                LIMIT 50000
            ];
		}
		List<Product_Group__c> result = new List<Product_Group__c>();
		for(Product_Group__c pg : ClsTriggerOpportunityHandler.productGroupList) {
			if(         criterium == 'id in productGroupIds'        && productGroupIds.contains(pg.Id) ) {
				result.add(pg);
			} else if ( criterium == 'name in productGroupNames'    && productGroupNames.contains(pg.Name) ) {
				result.add(pg);
			} else if ( criterium == 'id in pgList'                 && pgList.contains(pg.id) ) {
				result.add(pg);
			}
		}
		return result;
	}

    private static Set<String> productGroupNames;
    private static Set<String> getProductGroupNames(ClsWrappers.TriggerContext trgCtx) {
        if(ClsTriggerOpportunityHandler.productGroupNames == null) {
            ClsTriggerOpportunityHandler.productGroupNames = new Set<String>();
            for (sobject so : trgCtx.newList) {
                Opportunity oppy = (Opportunity)so;
                ClsTriggerOpportunityHandler.productGroupNames.add(oppy.Product_Primary_PG__c);
            }
        }
        return ClsTriggerOpportunityHandler.productGroupNames;
    }

	private static List<Id> pgList;
	private static List<Id> getPGList(ClsWrappers.TriggerContext trgCtx) {
		if(ClsTriggerOpportunityHandler.pgList == null) {
            ClsTriggerOpportunityHandler.pgList = new List<Id>();
			for (sobject so : trgCtx.newList)
			{
				Opportunity oppy = (Opportunity)so;
				if(oppy.Product_Group__c != null){
                    ClsTriggerOpportunityHandler.pgList.add(oppy.Product_Group__c);
				}
			}
		}
		return ClsTriggerOpportunityHandler.pgList;
	}

	private static Set<Id> productGroupIds;
	private static Set<Id> getProductGroupIds(ClsWrappers.TriggerContext trgCtx) {
		if(ClsTriggerOpportunityHandler.productGroupIds == null) {
            ClsTriggerOpportunityHandler.productGroupIds = new Set<ID>();
			for (Sobject sobj : trgCtx.newList) {
				Opportunity newOppy = (Opportunity)sobj;
				if (String.isNotBlank(newOppy.Product_Group__c)) {
                    ClsTriggerOpportunityHandler.productGroupIds.add(newOppy.Product_Group__c);
				}
			}
		}
		return ClsTriggerOpportunityHandler.productGroupIds;
	}
    // ALM-5127 END

    //SFDC-0245
    @TestVisible 
    private void updateServiceCategory(ClsWrappers.TriggerContext trgCtx) 
    {
        if (trgCtx.isBefore && (trgCtx.isInsert || trgCtx.isUpdate))
        {
            List<ID> pgList = ClsTriggerOpportunityHandler.getPGList(trgCtx);
            List<ID> locationList = new List<ID>();
            //note: (hardcoded values) - it should be formula field on Product_Group__c object 
            String servisCodes = '2222,2223,2413,2657,2851,2861,2869,2871,2872,2879,2885,2893,2901,3107,3129,3161,3442,4108,4131,4159,4179,4181,4204,4206,4333,4414,4449,4507,5502,7712,7713,9031';

            if(pgList.size()>0){
                // Map<Id, OpportunityHistory> historyMap = new Map<Id, OpportunityHistory>(historyList);
                Map<Id,Product_Group__c> pgDivMap = new Map<Id,Product_Group__c>(ClsTriggerOpportunityHandler.getProductGroups(trgCtx,'id in pgList'));
                Map<Id,ABB_Location__c> locDivMap = new Map<Id,ABB_Location__c>([select id, Div__c from ABB_Location__c where id=:locationList]);
                
                for (sobject so : trgCtx.newList) 
                {
                    Opportunity oppy = (Opportunity)so;
                    
                    Boolean isPA = (oppy.Product_Group__c != null && pgDivMap.containsKey(oppy.Product_Group__c) && pgDivMap.get(oppy.Product_Group__c).Division__c != null && pgDivMap.get(oppy.Product_Group__c).Division__c == 'IA')
                        || (oppy.ABB_Location__c != null && locDivMap.containsKey(oppy.ABB_Location__c) && locDivMap.get(oppy.ABB_Location__c).Div__c != null && locDivMap.get(oppy.ABB_Location__c).Div__c.startsWithIgnoreCase('IA'));
                    
                    Boolean isServiceGroup = oppy.Product_Group__c != null && pgDivMap.containsKey(oppy.Product_Group__c) && pgDivMap.get(oppy.Product_Group__c).Product_Group_Code__c != null && servisCodes.contains(pgDivMap.get(oppy.Product_Group__c).Product_Group_Code__c);
                    
                    if(oppy.Product_Group__c != null && !isPA && !isServiceGroup){
                        if(oppy.Service_Category__c == null || oppy.Service_Category__c == '')
                        {                                  
                            oppy.Service_Category__c = 'Non Service';
                        }
                    }

                }
            }
        }      
    }  
    
    /* Update Customer Preference in Opportunity*/
    @TestVisible
private void updateCustomerPreference(ClsWrappers.TriggerContext trgCtx) 
{
 if (trgCtx.isBefore && (trgCtx.isUpdate) || (trgCtx.isInsert))
    {
      for (sobject so : trgCtx.newList) 
            
        {
          Opportunity oppy = (Opportunity)so;
          if(oppy.Stagename.equals('Closed Won')){
          oppy.Sales_Pursuit_Progress__c = 'Won';
          if(oppy.Customer_Preference__c <> 'ABB'){
          oppy.Customer_Preference__c = 'ABB';
          
          }
        }
           else if(oppy.Stagename.equals('Closed Lost')){
           oppy.Sales_Pursuit_Progress__c = 'Lost';
           if(oppy.customer_Preference__c <> 'Competitor'){
           oppy.Customer_Preference__c = 'Competitor';
           
           }
         }
            else if(oppy.Stagename.equals('Closed Lost Without ABB Bid')){
            oppy.Sales_Pursuit_Progress__c = 'Lost Without ABB Bid';
            if(oppy.customer_Preference__c <> 'Competitor'){
            oppy.Customer_Preference__c = 'Competitor';
            
            }
        }
     }
  }
}

/**   
    * This method will intiate the copy Combined Pipeline class for Opportunity
    * Release R7 
    * @author  Hari Charan(Accenture)
    * @created  2017-07-02* @version 1.0
    *
    */    
    @TestVisible 
    private void intiaiteCombinedPipelineUtility(ClsWrappers.TriggerContext trgCtx){
        List<Id> newOpptyIds = new List<Id>();
        List<Opportunity> newOppList = new List<Opportunity>();
        Set<String> divNameSet = new Set<String>();
        for(Pipeline_Oppty_Div_Info__c rec: Pipeline_Oppty_Div_Info__c.getAll().Values()){
            divNameSet.add(rec.Name);
        }
        system.debug('divNameSet '+divNameSet);
        if (trgCtx.isAfter && (trgCtx.isUpdate || trgCtx.isInsert)){
            system.debug('trgCtx.isInsert '+trgCtx.isInsert);
            system.debug('trgCtx.isUpdate '+trgCtx.isUpdate);
            for (sobject so : trgCtx.newList){
                Opportunity oppy = (Opportunity)so;
                system.debug('oppy.ABB_Location_Div__c '+oppy.ABB_Location_Div__c); // Division__c
                if(((String.isNotEmpty(oppy.ABB_Location_Div__c) && divNameSet.contains(oppy.ABB_Location_Div__c)) || 
                     (String.isNotEmpty(oppy.Division__c) && divNameSet.contains(oppy.Division__c))) 
                    && String.isEmpty(oppy.Alternative_Opportunity_To__c)){
                    newOpptyIds.add(oppy.Id);
                    newOppList.add(oppy);
                }
            }
        }
        system.debug('newOpptyIds '+newOpptyIds );
        system.debug('newOppList '+newOppList );
        if(newOpptyIds.size()>0 &&newOpptyIds != NULL && newOppList.size()>0 && newOppList != NULL ){
            CombinedPipelineSenarioFindingGlobal clsUtil = new CombinedPipelineSenarioFindingGlobal();
            clsUtil.OpptytoCombinedPipelineMethod(newOpptyIds,newOppList); //OpptytoCombinedPipelineMethod(List<Id> newOpptyIds,List<Opportunity> newOppList)
        }
    }
    /**   
    * This method updateOpportunityBUFields
    * Release R7B 
    * @author  Hari Charan(Accenture)
    * @created  2017-19-05
    * @modified by: Indhu Ramalingam (Sts PR2.0 - to include the below logic in Lead Conversion process during update only)
    **/    
    @TestVisible 
    private void updateOpportunityBUFields(ClsWrappers.TriggerContext trgCtx){
        List<Id> ownerIds = new List<Id>();
        Map<Id,User> userMap = new Map<Id,User>();
        Set<String> applicationBU = new Set<String>();
        Set<String> businessLineBU = new Set<String>();
        Schema.DescribeFieldResult fieldResultBU = Opportunity.BU__c.getDescribe();    
        List<Schema.picklistEntry> pleBU = fieldResultBU.getPicklistValues();
        for(Schema.picklistEntry f : pleBU){    
            applicationBU.add(f.getValue());                    
        }    
        Schema.DescribeFieldResult fieldResultAbbDomain = Opportunity.ABB_Domain__c.getDescribe();    
        List<Schema.picklistEntry> pleAbbDomain = fieldResultAbbDomain.getPicklistValues();
        for(Schema.picklistEntry f : pleAbbDomain){    
            businessLineBU.add(f.getValue());                    
        }    
        if (trgCtx.isInsert || trgCtx.isUpdate){
            for (sobject so : trgCtx.newList){
                Opportunity oppy = (Opportunity)so;             
                if(trgCtx.isUpdate && oppy.Created_from_Lead__c) {
                    if(String.isBlank(oppy.BU__c) || String.isBlank(oppy.ABB_Domain__c) || String.isBlank(oppy.ABB_Location__c)){
                        ownerIds.add(oppy.OwnerId);
                    }
                }
                else if(trgCtx.isInsert) {
                    if(String.isBlank(oppy.BU__c) || String.isBlank(oppy.ABB_Domain__c)){
                        ownerIds.add(oppy.OwnerId);
                    }
                }
            }       
        
            if(!ownerIds.isEmpty()){
                for(User usr : [SELECT ID,Application_BU__c,Business_Line_BU__c, ABB_Location_ID__c, ABB_Location_BAL_ID__c FROM USER 
                                    WHERE ID IN:ownerIds AND Application_BU__c!=Null AND Business_Line_BU__c !=Null]){
                    userMap.put(usr.Id,Usr); 
                }
            }
            for(sobject so : trgCtx.newList){
                Opportunity oppy = (Opportunity)so;             
                if(trgCtx.isInsert || (trgCtx.isUpdate && oppy.Created_from_Lead__c)) {
                    if(userMap.containsKey(oppy.OwnerId)){
                        if(String.isBlank(oppy.BU__c)){
                            if(applicationBU.contains(userMap.get(oppy.OwnerId).Application_BU__c)){
                                oppy.BU__c = userMap.get(oppy.OwnerId).Application_BU__c;
                            }
                        }
                        if(String.isBlank(oppy.ABB_Domain__c)){
                            if(businessLineBU.contains(userMap.get(oppy.OwnerId).Business_Line_BU__c)){
                                oppy.ABB_Domain__c = userMap.get(oppy.OwnerId).Business_Line_BU__c;
                            }
                        }                       
                        if(trgCtx.isUpdate && oppy.Created_from_Lead__c) {
                            if(oppy.ABB_Location__c == null && userMap.get(oppy.OwnerId).ABB_Location_ID__c != null && userMap.get(oppy.OwnerId).ABB_Location_BAL_ID__c != null) {
                                oppy.ABB_Location__c = userMap.get(oppy.OwnerId).ABB_Location_ID__c;
                            }
                        }
                    }
                }
            }
            
        }
    }
     /** @author Amani Gudali
      *  @name chatterPostForPartnerCreatedOpportunity
      *  @Description Post a chatter feed to the ABB Channel Manager of the Partner User who created the Opportunity. 
      **/ 
    @TestVisible 
    private void chatterPostForPartnerCreatedOpportunity(ClsWrappers.TriggerContext trgCtx){
        id uId=userinfo.getuserid();
        String uName=userinfo.getname();
        User[] userList=[select id,Name,ABB_Manager__c,contact.Accountid,profile.Name,contact.name from user where id=:uId LIMIT 1];
        Map<String,Id> channelManagers=new Map<String,Id>();
        Map<String,String> conName=new Map<String,String>();
        if(!userList.IsEmpty())
        {
            for(User c:userList)
            {
                if(c.ABB_Manager__c!=null && c.Contact!=null && c.contact.Name!=null)
                {
                channelManagers.put(c.Name,c.ABB_Manager__c);
                conName.put(c.name,c.contact.Name); 
                }    
            }
            system.debug(channelManagers);
            if(channelManagers.containskey(uName))
            {
                for(sobject so : trgCtx.newList)
                {
                    Opportunity opp=(Opportunity)so;
                    ConnectApi.FeedElementCapabilitiesInput feedElementCapabilitiesInput = new ConnectApi.FeedElementCapabilitiesInput();
                    ConnectApi.FeedItemInput feedItemInput_1 = new ConnectApi.FeedItemInput();
                    ConnectApi.MentionSegmentInput mentionSegmentInput_1 = new ConnectApi.MentionSegmentInput();
                    ConnectApi.MessageBodyInput messageBodyInput_1 = new ConnectApi.MessageBodyInput();
                    ConnectApi.TextSegmentInput textSegmentInput_1 = new ConnectApi.TextSegmentInput();
                    messageBodyInput_1.messageSegments = new List<ConnectApi.MessageSegmentInput>();
                    textSegmentInput_1.text ='Your channel partner('+conName.get(uName)+') has created a new Opportunity';
                     
                    mentionSegmentInput_1.id =channelManagers.get(uName);
                    messageBodyInput_1.messageSegments.add(mentionSegmentInput_1);                                 
                    messageBodyInput_1.messageSegments.add(textSegmentInput_1);
                    
                    ConnectApi.LinkCapabilityInput capabilityInputLink1 = new ConnectApi.LinkCapabilityInput();

                    capabilityInputLink1.url = '/'+opp.id;
                    capabilityInputLink1.urlName = opp.Name;

                    feedElementCapabilitiesInput.link = capabilityInputLink1;
                    feedItemInput_1.capabilities = feedElementCapabilitiesInput;


                    feedItemInput_1.body = messageBodyInput_1;
                    feedItemInput_1.feedElementType = ConnectApi.FeedElementType.FeedItem;
                    feedItemInput_1.subjectId = opp.id;
                   
                    if(!Test.isRunningTest())
                    {
                        ConnectApi.FeedElement feedElement = ConnectApi.ChatterFeeds.postFeedElement(Network.getNetworkId(), feedItemInput_1);
                        
                    }
                }  
            }            
        }             
    }
    /*  Description of the purpose of the method. 
    *  @name addPartnersToOpportunityShare
    *  @Description - Add the parters of the account customer to the opportunity share for the current record.
    *  @return Nothing - 
    */
    @TestVisible
    public static void addPartnersToOpportunityShare(ClsWrappers.TriggerContext trgCtx)
    {    
        Id recurringOppRecordType = Schema.SObjectType.Opportunity.getRecordTypeInfosByName().get('Recurring Opportunity').getRecordTypeId();
        Set<id> accIds=new Set<id>();
        for (Sobject sobj : trgCtx.newList) 
        {
            Opportunity newOppy = (Opportunity)sobj;
            accIds.add(newOppy.Accountid);
        }
        Id uId=userinfo.getUserId();
        List<Id> accTeamUserId=new List<Id>();
        Map<id,List<Id>> accTeamMap=new Map<id,List<Id>>();
        for(Account_team__c accTeamMember:[SELECT User__c,Account_Access__c, Account__c, Team_Role__c FROM Account_team__c 
                                           where Account__c IN :accIds AND User__c!=:uid AND User__r.IsActive=true AND
                                           Account__r.IsPartner=true AND Account__r.owner.name='Partner Enabled Account' LIMIT 50000])
        {   
            if (accTeamMap.containsKey(accTeamMember.Account__c))
            {                    
                accTeamMap.get(accTeamMember.Account__c).add(accTeamMember.User__c);
            }
            else
            {
                accTeamMap.put(accTeamMember.Account__c,new List<Id> {accTeamMember.User__c});
            }
        }
        List<OpportunityShare> oppShareList=new List<OpportunityShare>();
        //Map<id,Account> partnerAcc=new Map<id,Account>([select id from Account where id IN :accIds AND IsPartner=true and owner.name='Partner Enabled Account' LIMIT 50000]);
        for (Sobject sobj : trgCtx.newList) 
        {
            Opportunity newOppy = (Opportunity)sobj;
            if(newOppy.RecordTypeId!=recurringOppRecordType)
            {
                if(accTeamMap.containskey(newOppy.Accountid))
                {
                    accTeamUserId=accTeamMap.get(newOppy.Accountid);
                    if(accTeamUserId!=null && !accTeamUserId.IsEmpty())
                    {
                        for(Id userId : accTeamUserId)
                        {
                            oppShareList.add(new OpportunityShare(OpportunityId=newOppy.id,UserOrGroupId=userId,OpportunityAccessLevel=System.label.System_CL00026,RowCause='Manual'));
                        }
                    }      
                } 
            }
        }
        Database.insert(oppShareList);
    }
    /* @Author : Hari Charan
    *  @Description: we will populate Sales pursuit progress,Customer buying path based on Stage and 
       Application BU,Business Line BU based on Offering Primary product group. 
    *  @Name: partnerOpportunityFieldAutoPopulations
    *  @return Nothing - 
    */
    @TestVisible
    public static void partnerOpportunityFieldAutoPopulations(ClsWrappers.TriggerContext trgCtx)
    {       
        User partnerProfileCheck = new User();
        partnerProfileCheck=[SELECT ID,Profile.Name from User Where Id=:userinfo.getUserId() LIMIT 1];
        Map<ID,Schema.RecordTypeInfo> rtype_Map = Opportunity.sObjectType.getDescribe().getRecordTypeInfosById();
        Map<String,PartnerSPPCBPMappingonStage__c> stageMapping = new Map<String,PartnerSPPCBPMappingonStage__c>();
        if(partnerProfileCheck.Profile.Name.equals(Label.SYS_ABBExtChannelPartnerCommunityUser) || 
            partnerProfileCheck.Profile.Name.equals(Label.SYS_ABB_Ext_Rep_Community_User) ||
            partnerProfileCheck.Profile.Name.equals(Label.SYS_ABB_Ext_Agent_Community_User)){
            Set<ID> productGroupIds = ClsTriggerOpportunityHandler.getProductGroupIds(trgCtx);
            Map<Id,String> pgBUMap = new Map<Id,String>();
            if(productGroupIds!=NULL && productGroupIds.size()>0){
                for(Product_Group__c pg: ClsTriggerOpportunityHandler.getProductGroups(trgCtx, 'id in productGroupIds')){
                    pgBUMap.put(pg.Id,pg.Business_Unit__c);
                }
            }
            for(PartnerSPPCBPMappingonStage__c mapping : PartnerSPPCBPMappingonStage__c.getall().values()){
                stageMapping.put(mapping.Name,mapping);
            }
            for (Sobject sobj : trgCtx.newList) {
                Opportunity newOppy = (Opportunity)sobj;
                //Use custom setting/Label here
                System.debug('newOppy.recordTypeID:'+newOppy.recordTypeID);
                if(rtype_Map.get(newOppy.recordTypeID).getName().containsIgnoreCase(Label.SYS_Opportunity_External_User)){
                    String Stage = newOppy.StageName;
                    if(stageMapping.containsKey(Stage)){
                        newOppy.Sales_Pursuit_Progress__c = stageMapping.get(Stage).Sales_Pursuit_Progress__c;
                        newOppy.Customer_Buying_Path__c = stageMapping.get(Stage).Customer_Buying_Path__c;
                    }
                    if(String.isNotBlank(newOppy.Product_Group__c)){
                        Schema.DescribeFieldResult fieldResultBU = Opportunity.BU__c.getDescribe();
                        List<Schema.PicklistEntry> pickValuesBU = fieldResultBU.getPicklistValues();
                        Set<String> ApplicationBu = new Set<String>();
                        for( Schema.PicklistEntry f : pickValuesBU){
                          ApplicationBu.add(f.getValue());
                        }
                        Schema.DescribeFieldResult fieldResultBusinessLineBU = Opportunity.ABB_Domain__c.getDescribe();
                        List<Schema.PicklistEntry> pickValuesBusinessLineBU = fieldResultBU.getPicklistValues();
                        Set<String> BusinessLineBU = new Set<String>();
                        for( Schema.PicklistEntry f : pickValuesBusinessLineBU){
                          BusinessLineBU.add(f.getValue());
                        }
                        if(pgBUMap.containsKey(newOppy.Product_Group__c) && ApplicationBu.contains(pgBUMap.get(newOppy.Product_Group__c))){
                            newOppy.BU__c = pgBUMap.get(newOppy.Product_Group__c);
                        }else{
                            newOppy.BU__c = 'All other BU\'s';
                        }
                        if(pgBUMap.containsKey(newOppy.Product_Group__c) && BusinessLineBU.contains(pgBUMap.get(newOppy.Product_Group__c))){
                            newOppy.ABB_Domain__c = pgBUMap.get(newOppy.Product_Group__c);
                        }else{
                            newOppy.ABB_Domain__c = '';    
                        }
                    }else{
                        newOppy.BU__c ='';
                        newOppy.ABB_Domain__c = '';
                    }
                } 
            }
        }
    }
    
     /* @Author : Hari Charan
    *  @Description: we will check User.Channel_Partner_GUID__c GUID values and query account and
    *  Validate Account Customer while creating Opportunity.
    *  @Name: partnerAccountValidation
    *  @return - Validation Error
    */
    @TestVisible
    public static void partnerAccountValidation(ClsWrappers.TriggerContext trgCtx){       
        User partnerProfileCheck = new User();
        partnerProfileCheck=[SELECT ID,Profile.Name,Channel_Partner_GUID__c,Contact.AccountId from User Where Id=:userinfo.getUserId() LIMIT 1];
        Map<ID,Schema.RecordTypeInfo> rtype_Map = Opportunity.sObjectType.getDescribe().getRecordTypeInfosById();
        Map<String,PartnerSPPCBPMappingonStage__c> stageMapping = new Map<String,PartnerSPPCBPMappingonStage__c>();
        if(partnerProfileCheck.Profile.Name.equals(Label.SYS_ABBExtChannelPartnerCommunityUser)){
            //SYS_ABBExtChannelPartnerCommunityUser--ABB Ext Channel Partner Community User
            Set<Id> accId = new Set<Id>();
            Map<ID,String> accIdGUIDMap = new Map<ID,String>();        
            for (Sobject sobj : trgCtx.newList) {
                Opportunity newOppy = (Opportunity)sobj;
                if(String.isNotBlank(newOppy.AccountId)){
                    accId.add(newOppy.AccountId);
                }
            }
            for(Account acc: [Select Id,GUID__c From Account Where Id IN:accId]){
                accIdGUIDMap.put(acc.Id,acc.GUID__c);
            }
            if(partnerProfileCheck.Channel_Partner_GUID__c != null) {
                List<String> guidSplit = partnerProfileCheck.Channel_Partner_GUID__c.split(';');
                Set<String> guidSplitSet = new Set<String>(guidSplit);
                for (Sobject sobj : trgCtx.newList) {
                    Opportunity newOppy = (Opportunity)sobj;
                    if(String.isNotBlank(newOppy.AccountId) && (newOppy.AccountId != partnerProfileCheck.Contact.AccountId)){
                        if(accIdGUIDMap.containsKey(newOppy.AccountId) && !guidSplitSet.contains(accIdGUIDMap.get(newOppy.AccountId))){         
                        newOppy.addError(Label.STS_PartnerAccountValidation);  
                        //STS_PartnerAccountValidation--Please Select Account Customer based on User Channel Partner GUID                   
                        }
                    }
                }
            }
        }
    }
    
    
    /* @Author : Hari Charan
    *  @Description: When Partner user share opportunity to ABB user then we will add partner to Opportunity Team.
    *  @Name: partnerasOpportunityTeamMember
    *  @return Nothing - 
    */
    @TestVisible
    public static void partnerasOpportunityTeamMember(ClsWrappers.TriggerContext trgCtx)
    {       
        User partnerProfileCheck = new User();
        partnerProfileCheck=[SELECT ID,Name,Profile.Name from User Where Id=:userinfo.getUserId() LIMIT 1];
        Map<ID,Schema.RecordTypeInfo> rtype_Map = Opportunity.sObjectType.getDescribe().getRecordTypeInfosById();
        if(partnerProfileCheck.Profile.Name.equals(Label.SYS_ABBExtChannelPartnerCommunityUser) || 
            partnerProfileCheck.Profile.Name.equals(Label.SYS_ABB_Ext_Rep_Community_User) ||
            partnerProfileCheck.Profile.Name.equals(Label.SYS_ABB_Ext_Agent_Community_User)){
            
            for (Sobject sobj : trgCtx.newList){
                
                Opportunity newOppy = (Opportunity)sobj;
                Opportunity oldOppy = (Opportunity)trgCtx.oldMap.get(newOppy.Id);
                //Use custom setting/Label here
                System.debug('newOppy.recordTypeID:'+newOppy.recordTypeID);
                if(rtype_Map.get(oldOppy.recordTypeID).getName().containsIgnoreCase(Label.SYS_Opportunity_External_User) && 
                    !rtype_Map.get(newOppy.recordTypeID).getName().containsIgnoreCase(Label.SYS_Opportunity_External_User)
                    && oldOppy.OwnerId!=newOppy.OwnerId){
                    OpportunityTeamMember otm = new OpportunityTeamMember();
                    //otm.Name=partnerProfileCheck.Name;
                    otm.OpportunityAccessLevel='Edit';
                    otm.OpportunityId=newOppy.Id;
                    otm.TeamMemberRole='Channel Partner';
                    otm.UserId=userinfo.getUserId();
                    try{
                        ClsTriggerOpportunityTeam.isSkipRecursiveOppTeamTrigger = true;
                        insert otm;
                    }catch(DMLException e){
                        System.debug('DML Error Occured::'+e);
                    }
                    
                } 
            }
        }
    }
  
    /**
    * @Author: Indhu Ramalingam
    * @name: updateAccEndUserFromEUP
    * @CreateDate: February 2018
    * @release: Sts PR2.0 Opportunity Management (Req - 5676) 
    * @Description: Account End User to be populated from EUP when: 
    *      a) when EUP is selected on the Opportunity, if End User Project is empty AND Account - End User is empty 
    *      b) when EUP is selected on the Opportunity, if End User Project is empty AND Account - End User is NOT empty and
    *        Root Account GUID for both accounts does not match.
    **/
    private static void updateAccEndUserFromEUP(ClsWrappers.TriggerContext trgCtx) {

        Opportunity newOpp;
        Opportunity oldOpp;
        Set<Id> endUserProjIdSet = new Set<Id>();
        Set<Id> accEndUserIdSet = new Set<Id>();
        List<Opportunity> opportunityList = new List<Opportunity>();
        Map<Id, End_User_Project__c> endUserProjMap = new Map<Id, End_User_Project__c>();
        Map<Id, Account> accEndUserMap = new Map<Id, Account>();
        String rootGUID = EMPTY_STRING;

        for(sObject so : trgCtx.newList) {
            newOpp = (Opportunity)so;
            if(trgCtx.isUpdate) {
                oldOpp = (Opportunity)trgCtx.oldMap.get(newOpp.Id);  
            }
            if((trgCtx.isInsert && newOpp.Account_End_User__c == null && newOpp.End_User_Project__c != null) ||
            (trgCtx.isUpdate && newOpp.Account_End_User__c == null && (oldOpp.End_User_Project__c == null || 
                                                                   (newOpp.End_User_Project__c != oldOpp.End_User_Project__c)))) {
                endUserProjIdSet.add(newOpp.End_User_Project__c);
                opportunityList.add(newOpp);
            }
            else if(trgCtx.isUpdate && newOpp.Account_End_User__c != null && (oldOpp.End_User_Project__c == null || 
                                                                            (newOpp.End_User_Project__c != oldOpp.End_User_Project__c))) {
                accEndUserIdSet.add(newOpp.Account_End_User__c);
                endUserProjIdSet.add(newOpp.End_User_Project__c);
                opportunityList.add(newOpp);
            }
      //Added for WA: 952 
      if(newOpp.Account_End_User__c != null && !accEndUserIdSet.contains(newOpp.Account_End_User__c)) {
        accEndUserIdSet.add(newOpp.Account_End_User__c);
      }
        }     
        if(endUserProjIdSet.size() > 0) {
            endUserProjMap = new Map<Id, End_User_Project__c>([SELECT Id, Name, Account_End_User__r.Root_Account_GUID__c, Account_End_User__c,
                        Account_End_User__r.Global_HQ_Name__c FROM End_User_Project__c WHERE Id IN :endUserProjIdSet LIMIT 50000]);
        }
        if(accEndUserIdSet.size() > 0) {
            accEndUserMap = new Map<Id, Account>([SELECT Id, Name, Root_Account_GUID__c, Global_HQ_Name__c FROM Account 
                                                    WHERE Id IN :accEndUserIdSet LIMIT 50000]);          
        }
        if(opportunityList.size() > 0) {
            for(Opportunity opp : opportunityList) {
                if(endUserProjMap.containsKey(opp.End_User_Project__c)) {
                    if(opp.Account_End_User__c == null) {
                        opp.Account_End_User__c = endUserProjMap.get(opp.End_User_Project__c).Account_End_User__c;         
                    }
                    else if(opp.Account_End_User__c != null) {
                        rootGUID = accEndUserMap.get(opp.Account_End_User__c).Root_Account_GUID__c;
                        if(rootGUID == null || (rootGUID != endUserProjMap.get(opp.End_User_Project__c).Account_End_User__r.Root_Account_GUID__c)) {
                            opp.Account_End_User__c = endUserProjMap.get(opp.End_User_Project__c).Account_End_User__c;  
                        }
                    }
                }
            }
        }
        //WA: 952 - To populate the technical field 'End User Global HQ Account' on Opportunity for End User Project lookup filter criteria
        for(sObject so : trgCtx.newList) {
            newOpp = (Opportunity)so;
            if(newOpp.Account_End_User__c != null) {
                if(accEndUserMap.containsKey(newOpp.Account_End_User__c)) {
                    if(accEndUserMap.get(newOpp.Account_End_User__c).Global_HQ_Name__c != null) {
                        newOpp.STS_End_User_Global_HQ_Account__c = accEndUserMap.get(newOpp.Account_End_User__c).Global_HQ_Name__c;
                    }
                    else {
                        newOpp.STS_End_User_Global_HQ_Account__c = newOpp.Account_End_User__c;
                    }
                }
                else if(endUserProjMap.containsKey(newOpp.End_User_Project__c) && endUserProjMap.get(newOpp.End_User_Project__c).Account_End_User__c != null && 
                        newOpp.Account_End_User__c == endUserProjMap.get(newOpp.End_User_Project__c).Account_End_User__c) {
                    if(endUserProjMap.get(newOpp.End_User_Project__c).Account_End_User__r.Global_HQ_Name__c != null) {
                        newOpp.STS_End_User_Global_HQ_Account__c = endUserProjMap.get(newOpp.End_User_Project__c).Account_End_User__r.Global_HQ_Name__c;
                    }
                    else {
                        newOpp.STS_End_User_Global_HQ_Account__c = newOpp.Account_End_User__c;
                    }
                }
            }   
            else if(newOpp.Account_End_User__c == null) {
                newOpp.STS_End_User_Global_HQ_Account__c = null;
            }
        }
    }
    
    /**   
    * @Author: Indhu Ramalingam
    * @name: probabilityRangeCheck
    * @CreateDate: February 2018
    * @release: Sts PR2.0 Opportunity Management (Req - 5690; User Story: 1336) 
    * @Description: User manual adjustment of probability that is still in the range of new level of probability should be retained. 
    *                 It should be overwritten ONLY when it's NOT within new level of range/last modified by System.
    **/
    private static void probabilityRangeCheck(ClsWrappers.TriggerContext trgCtx) {
    
        Map<String, STS_ProbabilityRange__c> mapRanges = STS_ProbabilityRange__c.getAll();      //Get values from Custom Settings
        List<String> percentRange = new List<String>(); 
        Opportunity oldOpp;
        Opportunity newOpp;
        Boolean isABBProb1NotNull;
        Boolean isABBProb2NotNull;
        
        Boolean isValueChanged;
        Id rbRecordTypeId = Schema.SObjectType.Opportunity.getRecordTypeInfosByName().get(Label.Recurring_Opportunity).getRecordTypeId();
        
        for (sobject so : trgCtx.newList) {            
            percentRange = new List<String>(); 
            newOpp = (Opportunity) so;
        
            if(trgCtx.oldMap != null){
                oldOpp = (Opportunity) trgCtx.oldMap.get(newOpp.id);
            }                   
            
            isABBProb1NotNull = newOpp.ABB_Background_Probability1__c != null ? true : false;           //Set boolean whether ABB_Background_Probability1__c is null or not null
            isABBProb2NotNull = newOpp.ABB_Background_Probability2__c != null ? true : false;           //Set boolean whether ABB_Background_Probability2__c is null or not null
            
            if(trgCtx.isUpdate) {
                isValueChanged = newOpp.Customer_Buying_Path__c != oldOpp.Customer_Buying_Path__c || newOpp.StageName != oldOpp.StageName
                                  || newOpp.Sales_Pursuit_Progress__c != oldOpp.Sales_Pursuit_Progress__c 
                                  || newOpp.Customer_Preference__c != oldOpp.Customer_Preference__c;                
            }           
            
            if(newOpp.RecordTypeId != rbRecordTypeId){
                //Moved the below logic from the Workflow 'Opportunity Probability Range Baseline'
                if(trgCtx.isInsert || isValueChanged) {                 
                    
                    if(isABBProb1NotNull) { 
                        newOpp.ABB_Probability_for_Range__c = newOpp.ABB_Background_Probability1__c; 
                    }
                    else if(isABBProb2NotNull) { 
                        newOpp.ABB_Probability_for_Range__c = newOpp.ABB_Background_Probability2__c; 
                    }
                    else { 
                        newOpp.ABB_Probability_for_Range__c = 0; 
                    }
                }
                
                //Moved the below logic from the Workflow 'Opportunity Probability Update'
                if(mapRanges.containsKey(String.valueOf(newOpp.ABB_Probability_for_Range__c)) 
                    && (trgCtx.isInsert || (newOpp.ABB_Probability__c == oldOpp.ABB_Probability__c && isValueChanged))) {                    
                                                
                    percentRange = (mapRanges.get(String.valueOf(newOpp.ABB_Probability_for_Range__c)).Probability_Range__c).split(Label.Sys_Comma);
                    
                    //Extra if condition added here to check whether the User entered Probability is within new level of Range
                    if(!percentRange.contains(String.valueOf(newOpp.ABB_Probability__c))
                                || (!String.isBlank(newOpp.ProbValue_ModifiedBy_Technical__c) && (STR_SYSTEM).equals(newOpp.ProbValue_ModifiedBy_Technical__c))) {
                        if(isABBProb1NotNull) {
                            newOpp.ABB_Probability__c = newOpp.ABB_Background_Probability1__c;
                        } 
                        else if(isABBProb2NotNull) { 
                            newOpp.ABB_Probability__c = newOpp.ABB_Background_Probability2__c;
                        }
                    }
                    else { break; }                                         
                }          
                
                //Check whether the Probability value is set by User or System
                if(trgCtx.isInsert || (newOpp.ABB_Probability__c != oldOpp.ABB_Probability__c &&
                                      ((isABBProb1NotNull && newOpp.ABB_Background_Probability1__c == oldOpp.ABB_Background_Probability1__c) ||
                                       (isABBProb2NotNull && newOpp.ABB_Background_Probability2__c == oldOpp.ABB_Background_Probability2__c)))) {
                    newOpp.ProbValue_ModifiedBy_Technical__c = Label.ClsTriggerCaseHandler_User;                                     //'User'
                }
                else if(trgCtx.isInsert || (newOpp.ABB_Probability__c != oldOpp.ABB_Probability__c &&
                                          ((isABBProb1NotNull && newOpp.ABB_Background_Probability1__c != oldOpp.ABB_Background_Probability1__c) ||
                                           (isABBProb2NotNull && newOpp.ABB_Background_Probability2__c != oldOpp.ABB_Background_Probability2__c)))) {
                    
                    if(newOpp.ABB_Background_Probability1__c == newOpp.ABB_Probability__c || newOpp.ABB_Background_Probability2__c == newOpp.ABB_Probability__c) {
                        newOpp.ProbValue_ModifiedBy_Technical__c = STR_SYSTEM; 
                    }
                }
            }
        }
    }
    
    /**   
    * @Author: Hari Charan
    * @name: altOppPrepopforOppUnderCase
    * @CreateDate: April 2018
    * @release: STS PR2.0 Opportunity Management for Partner Community Users. 
    * @Description: We are prepopulating Alternative opportunity for Opportunities which were created under Case Record.
    **/
    private static void altOppPrepopforOppUnderCase(ClsWrappers.TriggerContext trgCtx) {
        Opportunity newOpp;
        Set<Id> CaseIdSet = new Set<Id>();
        for (sobject so : trgCtx.newList){            
            newOpp = (Opportunity) so;
            if(newopp.STS_Prospect_based_opportunity__c!=NULL){
                CaseIdSet.add(newopp.STS_Prospect_based_opportunity__c);
                //newopp.Account_End_User__c=NULL;
            }
        }
        Map<Id,List<Id>> caseIdListOppIdMap = new Map<Id,List<Id>>();
        if(!CaseIdSet.isEmpty()){
            for(Opportunity opp : [Select Id,Name,STS_Prospect_based_opportunity__c From Opportunity 
                                    Where STS_Prospect_based_opportunity__c IN:CaseIdSet AND Alternative_Opportunity_To__c=NULL Limit 50000]){
                if (caseIdListOppIdMap.containsKey(opp.STS_Prospect_based_opportunity__c)){                    
                    caseIdListOppIdMap.get(opp.STS_Prospect_based_opportunity__c).add(opp.Id);
                }else{
                    caseIdListOppIdMap.put(opp.STS_Prospect_based_opportunity__c,new List<Id> {opp.Id});
                }
            }
        }
        system.debug('caseIdListOppIdMap:'+caseIdListOppIdMap);
        for (sobject so : trgCtx.newList){            
            newOpp = (Opportunity) so;
            if(newopp.STS_Prospect_based_opportunity__c!=NULL && caseIdListOppIdMap.containsKey(newopp.STS_Prospect_based_opportunity__c)
                && caseIdListOppIdMap.get(newopp.STS_Prospect_based_opportunity__c)[0]!=NULL){
                newopp.Alternative_Opportunity_To__c=caseIdListOppIdMap.get(newopp.STS_Prospect_based_opportunity__c)[0];
            }
        }

    }

    /**   
    * @Author: Indhu Ramalingam
    * @name: probabilityRangeCheck
    * @CreateDate: February 2018
    * @release: Sts PR2.0 Opportunity Management (Req - 5690; User Story: 1336) 
    * @Description: User manual adjustment of probability that is still in the range of new level of probability should be retained. 
    *                 It should be overwritten ONLY when it's NOT within new level of range/last modified by System;
    *                 Method is being called in after trigger only for Portal Users as the fields SPP, CP are auto populated using trigger
    *                 and the background formula fields are calculated only after the values are saved.
    **/
    private static void probabilityRangeCheckForPortalUsers(ClsWrappers.TriggerContext trgCtx) {
        
        //Calling the method from the helper class by passing the trigger list
        STS_ClsTriggerOpportunityHelper.probabilityCheckForExternalUsers(trgCtx);       
    }
    
    /**
      @Author Lalitha
      @name: updateOpportunityCreatedInLead
      @CreateDate: 24/02/2017
      @Description  Rel2.0 WA:955 When portal user creates opportunity from the lead ,
      STS_Prospect_based_opportunity__c  will be updated with Lead ID and Once opp is inserted,
      Opportunity_was_created__c checkbox is set to true.
      @Version 1.0
     **/ 
    @TestVisible 
    private void updateOpportunityCreatedInLead(ClsWrappers.TriggerContext trgCtx){    
        list<Lead> lstLeads = new List<Lead>();
         for(sobject so : trgCtx.newList)
                {
                    Opportunity opp=(Opportunity)so;
                    if(opp.STS_Prospect_based_opportunity__c != NULL ){
                        ID leadID = opp.STS_Prospect_based_opportunity__c;                       
                        Lead leadRec = new Lead(ID=leadID);
                        leadRec.Opportunity_was_created__c = True;                        
                        lstLeads.add(leadRec);
                    }                    
                }                
                List<Database.SaveResult> results = Database.update(lstLeads, false);      
                for (Database.SaveResult sr : results ) {
                    if (!sr.isSuccess()) { // Operation failed, so get all errors                        
                        for(Database.Error err : sr.getErrors()) {                                        
                            System.debug(err.getStatusCode() +Label.System_Colon+err.getMessage());                    
                        }
                    }
                }      
    }
private static void commitAndTargetUpdate(ClsWrappers.TriggerContext trgCtx)
    {
        for (Sobject sobj : trgCtx.newList) {
            Opportunity newOppy = (Opportunity)sobj;

            if (newOppy.Commit__c) { //commit populated
                newOppy.Target__c = true;
                newOppy.Commit_Set_Timestamp__c = Datetime.now();
                newOppy.Commit_Set_User__c = UserInfo.getFirstName() + ' ' + UserInfo.getLastName();
                newOppy.Target_Set_Timestamp__c = Datetime.now();
                newOppy.Target_Set_User__c = UserInfo.getFirstName() + ' ' + UserInfo.getLastName();
            }
            else if (!newOppy.Commit__c && newOppy.Target__c) { //commit empty and target populated
                newOppy.Target_Set_Timestamp__c = Datetime.now();
                newOppy.Target_Set_User__c = UserInfo.getFirstName() + ' ' + UserInfo.getLastName();
                newOppy.Commit_Set_Timestamp__c = null;
                newOppy.Commit_Set_User__c = null;
            }
            else if (!newOppy.Commit__c && !newOppy.Target__c) { //commit and target empty
                newOppy.Commit_Set_Timestamp__c = null;
                newOppy.Commit_Set_User__c = null;
                newOppy.Target_Set_Timestamp__c = null;
                newOppy.Target_Set_User__c = null;
            }
        }
    }
}