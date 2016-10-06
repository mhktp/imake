var response = require('cfn-response');
exports.handler = function (event, context) {
  console.log('REQUEST RECEIVED:\\n', JSON.stringify(event));
  if (event.RequestType == 'Delete') {
    response.send(event, context, response.SUCCESS);
    return;
  }
  var stackName = event.ResourceProperties.StackName;
  var responseData = {};
  if (stackName) {
    var aws = require('aws-sdk');
    var cfn = new aws.CloudFormation();
    cfn.listStackResources({StackName: stackName}, function (err, data) {
      if (err) {
        responseData = {Error: 'listStackResources call failed'};
        console.log(responseData.Error + ':\n', err);
        response.send(event, context, response.FAILED, responseData);
      }
      else {
        data.StackResourceSummaries.forEach(function (output) {
          responseData[output.LogicalResourceId] = output.PhysicalResourceId;
        });
        response.send(event, context, response.SUCCESS, responseData);
      }
    });
  } else {
    responseData = {Error: 'Stack name not specified'};
    console.log(responseData.Error);
    response.send(event, context, response.FAILED, responseData);
  }
};